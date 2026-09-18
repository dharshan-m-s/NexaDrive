import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/api.dart';
import 'services/background_transfer_service.dart';
import 'services/session.dart';
import 'core/design/app_theme.dart';
import 'ui/screens/login/login_screen.dart';
import 'ui/shell/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

  const NexaDriveApp({
    super.key,
    required this.session,
    required this.prefs,
    this.api,
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
          home: widget.session.token == null
              ? LoginScreen(session: widget.session)
              : AppShell(
                  session: widget.session,
                  prefs: widget.prefs,
                  api: widget.api,
                ),
        );
      },
    );
  }
}
