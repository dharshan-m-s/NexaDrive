import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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

  // Full-bleed edge-to-edge: the app paints behind the system status and
  // navigation bars, so the app's background extends seamlessly under the
  // notification panel instead of reading as a separate theme. Content is
  // still inset by SafeArea, so nothing is clipped; icon legibility follows
  // the active theme via AnnotatedRegion below.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

  debugPaintBaselinesEnabled = false;
  debugPaintSizeEnabled = false;
  debugPaintLayerBordersEnabled = false;
  debugPaintPointersEnabled = false;
  debugPaintTextLayoutBoxes = false;
  debugRepaintRainbowEnabled = false;
  debugRepaintTextRainbowEnabled = false;
  debugDisableClipLayers = false;
  debugDisablePhysicalShapeLayers = false;

  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = 150 * 1024 * 1024
    ..maximumSize = 200;

  final session = Session();
  await session.load();
  if (session.token != null) {
    await BackgroundTransferService.schedule();
  }

  final prefs = await SharedPreferences.getInstance();

  runApp(NexaDriveApp(session: session, prefs: prefs));
}

class NexaDriveApp extends StatefulWidget {
  final Session session;
  final SharedPreferences prefs;
  final Api? api;
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
        final platformBrightness =
            WidgetsBinding.instance.platformDispatcher.platformBrightness;
        final dark = mode == 'dark'
            ? true
            : mode == 'light'
                ? false
                : platformBrightness == Brightness.dark;

        // Mirrors the active app theme onto the system bars that now sit over
        // the app's background: transparent chrome, icons in the right contrast.
        final overlay = SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
          statusBarBrightness: dark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness:
              dark ? Brightness.light : Brightness.dark,
          systemNavigationBarDividerColor: Colors.transparent,
        );

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlay,
          child: MaterialApp(
            title: 'NexaDrive',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: mode == 'light'
                ? ThemeMode.light
                : mode == 'dark'
                    ? ThemeMode.dark
                    : ThemeMode.system,
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
          ),
        );
      },
    );
  }
}
