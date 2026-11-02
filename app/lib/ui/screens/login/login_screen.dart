import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../services/api.dart';
import '../../../services/background_transfer_service.dart';
import '../../../services/session.dart';
import '../../shell/app_shell.dart';
import '../../widgets/nexa_components.dart';

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

  /// Client-side validation, run before any request leaves the device.
  ///
  /// Without it an empty form was posted verbatim and the user saw whatever
  /// transport exception the address produced, which reads as a server fault
  /// rather than "you have not filled the form in yet".
  String? _validationError() {
    const badAddress = 'That does not look like a server address. '
        'Try https://server.example.com';
    final address = server.text.trim();
    if (address.isEmpty) return 'Enter the address of your NexaDrive server.';
    // The address is normalised the same way [Session] normalises it, so a
    // bare hostname (no scheme) is still accepted and defaults to HTTPS.
    final normalized = Session.normalizeServerUrl(address);
    // Whitespace anywhere is rejected up front: Uri.tryParse is lenient enough
    // to read "not a url" as host "not" plus a path, which would sail past a
    // host-only check and become a real request to the wrong origin.
    if (normalized.contains(RegExp(r'\s'))) return badAddress;
    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.isEmpty) return badAddress;
    if (username.text.trim().isEmpty) return 'Enter your username.';
    if (password.text.isEmpty) return 'Enter your password.';
    return null;
  }

  Future<void> submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (loading) return;

    final invalid = _validationError();
    if (invalid != null) {
      setState(() {
        error = invalid;
        loading = false;
      });
      return;
    }

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
      // The screen can be popped while the request is in flight; calling
      // setState on a disposed State throws.
      if (!mounted) return;
      setState(() {
        error = _friendlyError(e);
        loading = false;
      });
    }
  }

  /// Turns a failure into one actionable sentence. Server-authored messages
  /// are surfaced as-is; transport failures become a network hint rather than
  /// a raw exception string.
  String _friendlyError(Object e) {
    if (e is ApiException) {
      switch (e.status) {
        case 401:
          return 'Username or password is incorrect.';
        case 403:
          return 'This account is blocked. Ask an administrator to unblock it.';
        case 429:
          return 'Too many sign-in attempts. Wait a few minutes and try again.';
        default:
          if (e.status >= 500) {
            return 'The server could not sign you in. Try again in a moment.';
          }
          return e.message;
      }
    }
    final text = e.toString().toLowerCase();
    if (text.contains('timeout') ||
        text.contains('connection') ||
        text.contains('socket') ||
        text.contains('host lookup') ||
        text.contains('network')) {
      return "Can't reach that server. Check the address and your network "
          'connection.';
    }
    return 'Sign-in failed. Check the server address and try again.';
  }

  @override
  void dispose() {
    server.dispose();
    username.dispose();
    password.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------- fragments

  /// The app mark: a rounded-square "app icon" carrying the cloud glyph, with
  /// a soft accent glow so it reads as a brand object rather than a flat shape.
  Widget _brandTile(Brightness brightness) {
    final accent = AppColors.accentFor(brightness);
    final onAccent =
        brightness == Brightness.dark ? Colors.black : Colors.white;

    return Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(AppDimens.radiusLarge),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(
              alpha: brightness == Brightness.dark ? 0.30 : 0.28,
            ),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Icon(Icons.cloud_rounded, color: onAccent, size: 34),
    );
  }

  /// The greeting. The subtitle is kept in the tree but taken out of layout on
  /// short viewports (Offstage) so shrinking the viewport never reshuffles —
  /// and therefore never unmounts — the fields below it.
  Widget _heading({required Brightness brightness, required bool short}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Welcome to NexaDrive',
          textAlign: TextAlign.center,
          style: AppTextStyle.heroTitle.copyWith(
            fontSize: short ? 22 : 32,
            color: AppColors.labelPrimaryFor(brightness),
          ),
        ),
        Offstage(
          offstage: short,
          child: Padding(
            padding: const EdgeInsets.only(top: AppDimens.space6),
            child: Text(
              'Your files. Your server. Your private cloud.',
              textAlign: TextAlign.center,
              style: AppTextStyle.callout.copyWith(
                color: AppColors.labelSecondaryFor(brightness),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fields({required bool dense, required Brightness brightness}) {
    // AutofillGroup lets a password manager populate all three fields as one
    // credential set instead of filling only whichever field has focus.
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NexaTextField(
            controller: server,
            label: 'Server address',
            hint: 'https://server.example.com',
            keyboardType: TextInputType.url,
            autofillHints: const [AutofillHints.url],
            prefixIcon:
                const Icon(Icons.dns_outlined, size: AppDimens.iconMedium),
            textInputAction: TextInputAction.next,
            dense: dense,
            onSubmitted: (_) =>
                FocusScope.of(context).requestFocus(_usernameFocus),
          ),
          SizedBox(height: dense ? AppDimens.space8 : AppDimens.space12),
          NexaTextField(
            controller: username,
            label: 'Username',
            hint: 'Enter your username',
            autofillHints: const [AutofillHints.username],
            prefixIcon: const Icon(Icons.person_outline_rounded,
                size: AppDimens.iconMedium),
            textInputAction: TextInputAction.next,
            focusNode: _usernameFocus,
            dense: dense,
            onSubmitted: (_) =>
                FocusScope.of(context).requestFocus(_passwordFocus),
          ),
          SizedBox(height: dense ? AppDimens.space8 : AppDimens.space12),
          NexaTextField(
            controller: password,
            dense: dense,
            label: 'Password',
            hint: 'Enter your password',
            obscureText: _obscure,
            autofillHints: const [AutofillHints.password],
            prefixIcon: const Icon(Icons.lock_outline_rounded,
                size: AppDimens.iconMedium),
            suffixIcon: IconButton(
              tooltip: _obscure ? 'Show password' : 'Hide password',
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: AppDimens.iconMedium,
              ),
            ),
            textInputAction: TextInputAction.done,
            focusNode: _passwordFocus,
            onSubmitted: (_) => submit(),
          ),
        ],
      ),
    );
  }

  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();

  Widget _submitButton() {
    return SizedBox(
      height: AppDimens.touchTargetLarge,
      child: NexaFilledButton(
        onPressed: loading ? null : submit,
        isLoading: loading,
        fullWidth: true,
        child: const Text('Sign in'),
      ),
    );
  }

  Widget _caption({required Brightness brightness}) {
    return Text(
      'Your files stay on a server you control.',
      textAlign: TextAlign.center,
      style: AppTextStyle.footnote.copyWith(
        color: AppColors.labelTertiaryFor(brightness),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 700;

    return Scaffold(
      backgroundColor: AppColors.backgroundFor(brightness),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Short viewports (phone in landscape, a desktop window, or the
            // keyboard opening) collapse the decorative masthead and tighten
            // the spacing so the primary action always stays on screen.
            //
            // Important: every block stays in the tree — the short-viewport
            // treatment uses Offstage, which removes a block from layout
            // without unmounting it. Swapping children in and out by height
            // reshuffles the column, unmounts the focused field and the IME
            // snaps shut; this layout cannot do that.
            final short = constraints.maxHeight < 600;
            final horizontal =
                wide ? AppDimens.pageMarginWide : AppDimens.pageMargin;
            final vertical = short ? AppDimens.space12 : AppDimens.space32;
            final minHeight = (constraints.maxHeight - vertical * 2)
                .clamp(0.0, double.infinity);

            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.symmetric(
                horizontal: horizontal,
                vertical: vertical,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Masthead: app mark, kept centred in the column.
                        Offstage(
                          offstage: short,
                          child: Center(child: _brandTile(brightness)),
                        ),
                        SizedBox(
                          height: short ? 0 : AppDimens.space20,
                        ),
                        // Greeting.
                        _heading(brightness: brightness, short: short),
                        SizedBox(
                          height: short ? AppDimens.space8 : AppDimens.space24,
                        ),
                        // Credentials.
                        _fields(dense: short, brightness: brightness),
                        // Inline, actionable error.
                        if (error != null) ...[
                          const SizedBox(height: AppDimens.space12),
                          _ErrorBanner(message: error!),
                        ],
                        SizedBox(
                          height: short ? AppDimens.space8 : AppDimens.space16,
                        ),
                        // Primary action.
                        _submitButton(),
                        // Quiet footer.
                        Offstage(
                          offstage: short,
                          child: Padding(
                            padding:
                                const EdgeInsets.only(top: AppDimens.space20),
                            child: _caption(brightness: brightness),
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
    final error = AppColors.errorFor(brightness);

    return Container(
      padding: const EdgeInsets.all(AppDimens.space12),
      decoration: BoxDecoration(
        color: error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: AppDimens.iconSmall,
            color: error,
          ),
          const SizedBox(width: AppDimens.space8),
          Expanded(
            child: Text(
              message,
              style: AppTextStyle.caption1.copyWith(
                color: AppColors.labelPrimaryFor(brightness),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
