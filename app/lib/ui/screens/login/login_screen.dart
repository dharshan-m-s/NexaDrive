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

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 700;
    final brightness = Theme.of(context).brightness;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
              padding: EdgeInsets.symmetric(
                horizontal: compact
                    ? AppDimens.pageMargin
                    : AppDimens.pageMarginWide,
                vertical: AppDimens.space32,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight -
                      (AppDimens.space32 * 2),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Brand mark
                        Container(
                          width: 62,
                          height: 62,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.accentFor(brightness),
                            borderRadius:
                                BorderRadius.circular(AppDimens.radiusCard),
                          ),
                          child: Icon(
                            Icons.cloud_rounded,
                            color: brightness == Brightness.dark
                                ? AppColors.textOnPrimaryDark
                                : Colors.white,
                            size: 32,
                          ),
                        ),
                        const SizedBox(height: AppDimens.space28),
                        Text(
                          'Welcome to NexaDrive',
                          style: AppTextStyle.display.copyWith(
                            color: AppColors.textPrimaryFor(brightness),
                          ),
                        ),
                        const SizedBox(height: AppDimens.space6),
                        Text(
                          'Your files. Your server. Your private cloud.',
                          style: AppTextStyle.rowSubtitle.copyWith(
                            color: AppColors.textSecondaryFor(brightness),
                          ),
                        ),
                        const SizedBox(height: AppDimens.space32),
                        TextField(
                          controller: server,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.next,
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
                            prefixIcon:
                                Icon(Icons.person_outline_rounded),
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
                            prefixIcon:
                                const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              tooltip: _obscure
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
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
                        const SizedBox(height: AppDimens.space24),
                        SizedBox(
                          height: AppDimens.touchTargetLarge,
                          child: FilledButton(
                            onPressed: loading ? null : submit,
                            child: loading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Sign in'),
                          ),
                        ),
                        const SizedBox(height: AppDimens.space20),
                        Text(
                          'Private cloud on hardware you control. Enter the address of your NexaDrive server.',
                          textAlign: TextAlign.center,
                          style: AppTextStyle.caption.copyWith(
                            color: AppColors.textTertiaryFor(brightness),
                          ),
                        ),
                      ],
                    ),
                  ),
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