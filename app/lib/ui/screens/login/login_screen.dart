import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../services/api.dart';
import '../../../services/background_transfer_service.dart';
import '../../../services/session.dart';
import '../../shell/app_shell.dart';

class LoginScreen extends StatefulWidget {
  final Session session;
  const LoginScreen({super.key, required this.session});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final server = TextEditingController();
  final username = TextEditingController();
  final password = TextEditingController();
  bool loading = false;
  String? error;
  bool _obscure = true;

  // ---- TS diagnosis (temporary) ----
  static final String _ts = DateTime.now().toIso8601String();
  final _fServer = FocusNode();
  final _fUsername = FocusNode();
  final _fPassword = FocusNode();
  String _log(String s) {
    debugPrint('[TS ${(DateTime.now().millisecondsSinceEpoch % 1000000)}] $s');
    return s;
  }
  // ---- /TS diagnosis ----

  /// Below this available height the centred composition no longer fits and the
  /// layout switches to a pinned primary action.
  ///
  /// Chosen from measurement, not taste: the centred form is ~538px tall, so a
  /// 464px window (a small Linux window, a phone in landscape, or a phone with
  /// the on-screen keyboard open) put "Sign in" 74px below the fold — a real
  /// tap target that cannot be tapped.
  static const double _shortViewport = 500;

  @override
  void initState() {
    super.initState();
    if (widget.session.serverUrl != null) {
      server.text = widget.session.serverUrl!;
    } else if (widget.session.username != null) {
      username.text = widget.session.username!;
    }
  }

  Future<void> submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final api = Api(widget.session);
      final result = await api.login(
        server.text.trim(),
        username.text.trim(),
        password.text,
      );
      final user = result['user'] as Map<String, dynamic>;
      await widget.session.save(
        serverUrl: server.text.trim(),
        token: result['token'] as String,
        displayName: user['display_name'] as String,
        username: user['username'] as String,
        role: user['role'] as String? ?? 'user',
        userId: user['id'] as String?,
      );

      await BackgroundTransferService.schedule();

      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AppShell(session: widget.session, prefs: prefs),
        ),
      );
    } catch (e) {
      setState(() {
        error = _friendlyError(e);
        loading = false;
      });
    }
  }

  String _friendlyError(Object e) {
    final text = e.toString();
    if (text.toLowerCase().contains('timeout') ||
        text.toLowerCase().contains('connection')) {
      return 'Can\'t reach that server. Check the address and your network connection.';
    }
    if (text.toLowerCase().contains('401') ||
        text.toLowerCase().contains('invalid')) {
      return 'Username or password is incorrect.';
    }
    return text;
  }

  @override
  void dispose() {
    server.dispose();
    username.dispose();
    password.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------- fragments

  Widget _brand(Brightness brightness, {required bool compact}) {
    final size = compact ? 44.0 : 62.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.accentFor(brightness),
        borderRadius: BorderRadius.circular(AppDimens.radiusCard),
      ),
      child: Icon(
        Icons.cloud_rounded,
        color: brightness == Brightness.dark
            ? AppColors.textOnPrimaryDark
            : Colors.white,
        size: compact ? 24 : 32,
      ),
    );
  }

  Widget _heading(Brightness brightness, {required bool compact}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Welcome to NexaDrive',
          style: (compact ? AppTextStyle.pageTitle : AppTextStyle.display)
              .copyWith(color: AppColors.textPrimaryFor(brightness)),
        ),
        const SizedBox(height: AppDimens.space4),
        Text(
          'Your files. Your server. Your private cloud.',
          style: AppTextStyle.rowSubtitle.copyWith(
            color: AppColors.textSecondaryFor(brightness),
          ),
        ),
      ],
    );
  }

  Widget _fields(Brightness brightness, {required bool compact}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: server,
          keyboardType: TextInputType.url,
          autofillHints: const [AutofillHints.url],
          decoration: InputDecoration(
            labelText: 'Server address',
            prefixIcon: const Icon(Icons.dns_outlined),
            hintText: compact
                ? 'https://server.example.com'
                : 'https://server.example.com or http://<lan-ip>:8080',
          ),
        ),
        const SizedBox(height: AppDimens.space12),
        TextField(
          controller: username,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username],
          decoration: const InputDecoration(
            labelText: 'Username',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
        ),
        const SizedBox(height: AppDimens.space12),
        TextField(
          controller: password,
          obscureText: _obscure,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => submit(),
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              tooltip: _obscure ? 'Show password' : 'Hide password',
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: AppDimens.space16),
          _ErrorBanner(message: error!),
        ],
      ],
    );
  }

  Widget _submitButton() {
    return SizedBox(
      height: AppDimens.touchTargetLarge,
      child: FilledButton(
        onPressed: loading ? null : submit,
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Sign in'),
      ),
    );
  }

  Widget _caption(Brightness brightness) {
    return Text(
      'Private cloud on hardware you control. Enter the address of your NexaDrive server.',
      textAlign: TextAlign.center,
      style: AppTextStyle.caption.copyWith(
        color: AppColors.textTertiaryFor(brightness),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 700;

    return Scaffold(
      // Let Scaffold apply the normal Android IME inset handling. The login
      // content remains one stable scrollable subtree while the keyboard opens;
      // it never swaps between two different widget trees based on height.
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final shortViewport = constraints.maxHeight < _shortViewport;
            final horizontal = compact
                ? AppDimens.pageMargin
                : AppDimens.pageMarginWide;
            final vertical = shortViewport
                ? AppDimens.space16
                : AppDimens.space32;

            return SingleChildScrollView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.symmetric(
                horizontal: horizontal,
                vertical: vertical,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 440,
                  minHeight: (constraints.maxHeight - vertical * 2)
                      .clamp(0.0, double.infinity),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: shortViewport
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _brand(brightness, compact: shortViewport),
                    ),
                    SizedBox(
                      height: shortViewport
                          ? AppDimens.space12
                          : AppDimens.space28,
                    ),
                    _heading(brightness, compact: shortViewport),
                    SizedBox(
                      height: shortViewport
                          ? AppDimens.space16
                          : AppDimens.space32,
                    ),
                    _fields(brightness, compact: shortViewport),
                    const SizedBox(height: AppDimens.space24),
                    _submitButton(),
                    const SizedBox(height: AppDimens.space20),
                    _caption(brightness),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.all(AppDimens.space12),
      decoration: BoxDecoration(
        color: (brightness == Brightness.dark ? AppColors.errorDark : AppColors.errorLight)
            .withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppDimens.radiusInner),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: AppDimens.iconSmall,
            color: brightness == Brightness.dark ? AppColors.errorDark : AppColors.errorLight,
          ),
          const SizedBox(width: AppDimens.space8),
          Expanded(
            child: Text(
              message,
              style: AppTextStyle.caption.copyWith(
                color: AppColors.textPrimaryFor(brightness),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
