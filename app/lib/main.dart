import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/api.dart';
import 'services/app_lock.dart';
import 'services/background_transfer_service.dart';
import 'services/session.dart';
import 'core/design/app_theme.dart';
import 'ui/screens/login/login_screen.dart';
import 'ui/shell/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Never start a normal app session with Flutter's rendering diagnostics
  // enabled. The flags themselves are plain runtime bools, but every paint
  // site that honours them is wrapped in `assert(() { ... }())`, so a release
  // build cannot draw these overlays. Clearing them unconditionally (rather
  // than inside an assert, which release strips) simply guarantees a clean
  // debug/profile session and costs nothing in production.
  //
  // These are NOT the cause of the "yellow double underline" that affected the
  // routed Update Center / Users pages. That was Flutter's `_errorTextStyle`
  // fallback for text outside a Material; see `OneUiPage`.
  debugPaintBaselinesEnabled = false;
  debugPaintSizeEnabled = false;
  debugPaintLayerBordersEnabled = false;
  debugPaintPointersEnabled = false;
  debugPaintTextLayoutBoxes = false;
  debugRepaintRainbowEnabled = false;
  debugRepaintTextRainbowEnabled = false;
  debugDisableClipLayers = false;
  debugDisablePhysicalShapeLayers = false;
  // Cache management: decoded frames only. The raw thumbnail/original byte
  // caches live in ImageRepository (services/image_pipeline.dart) and are
  // bounded separately, so this budget covers decoded tiles plus the couple of
  // full-resolution frames the viewer holds without risking an OOM on a
  // low-end phone.
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = 150 * 1024 * 1024
    ..maximumSize = 200;
  final session = Session();
  await session.load();
  if (session.token != null) {
    await BackgroundTransferService.schedule();
  }

  // The Update Center reuses the same preferences instance for its check
  // bookkeeping (last check time, latest known version, cached manifest).
  final prefs = await SharedPreferences.getInstance();

  runApp(NexaDriveApp(session: session, prefs: prefs));
}

class NexaDriveApp extends StatefulWidget {
  final Session session;
  final SharedPreferences prefs;

  /// Test seam: lets a test drive the signed-in shell against a scripted
  /// server. Null in production, where the shell builds its own client.
  final Api? api;

  /// Test seam: replaces the App Lock platform adapter. Null in production,
  /// where the gate talks to the Android host over its method channel.
  final AppLockService? appLock;

  const NexaDriveApp({
    super.key,
    required this.session,
    required this.prefs,
    this.api,
    this.appLock,
  });

  @override
  State<NexaDriveApp> createState() => _NexaDriveAppState();
}

class _NexaDriveAppState extends State<NexaDriveApp> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final mode = widget.session.themeMode;
        return MaterialApp(
          title: 'NexaDrive',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode == 'light'
              ? ThemeMode.light
              : mode == 'dark'
                  ? ThemeMode.dark
                  : ThemeMode.system,
          // The gate sits above every signed-in screen so App Lock covers
          // all of them at once; when the setting is off (or the platform has
          // no implementation) it renders the child untouched.
          home: widget.session.token == null
              ? LoginScreen(session: widget.session)
              : AppLockGate(
                  service: widget.appLock ?? AppLockService(),
                  child: AppShell(
                    session: widget.session,
                    prefs: widget.prefs,
                    api: widget.api,
                  ),
                ),
        );
      },
    );
  }
}
