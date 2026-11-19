import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/design/app_dimensions.dart';
import '../../../core/design/app_typography.dart';
import '../../../services/api.dart';
import '../../../services/background_transfer_service.dart';
import '../../../services/session.dart';
import '../../shell/app_shell.dart';
import '../../widgets/nexa_text_field.dart';

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

  /// The app mark: a tonal Material card carrying the cloud glyph. Its
  /// separation comes from the `primaryContainer` role, not a custom shadow.
  Widget _brandTile() {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      surfaceTintColor: Colors.transparent,
      elevation: AppDimens.elevationSubtle,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.radiusLarge),
      ),
      child: SizedBox(
        width: AppDimens.iconHero,
        height: AppDimens.iconHero,
        child: Center(
          child: Icon(
            Icons.cloud_rounded,
            size: AppDimens.iconTileLarge,
            color: scheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }

  /// The greeting. The subtitle is kept in the tree but taken out of layout on
  /// short viewports (Offstage) so shrinking the viewport never reshuffles —
  /// and therefore never unmounts — the fields below it.
  Widget _heading({required bool short}) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Sign in to your cloud',
          textAlign: TextAlign.center,
          style: (short ? AppTextStyle.headlineSmall : AppTextStyle.display)
              .copyWith(color: scheme.onSurface),
        ),
        Offstage(
          offstage: short,
          child: Padding(
            padding: const EdgeInsets.only(top: AppDimens.space6),
            child: Text(
              'Connect to your private cloud.',
              textAlign: TextAlign.center,
              style: AppTextStyle.bodyMedium.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fields({required bool dense}) {
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
            prefixIcon: const Icon(Icons.dns_outlined),
            textInputAction: TextInputAction.next,
            dense: dense,
            onFieldSubmitted: (_) =>
                FocusScope.of(context).requestFocus(_usernameFocus),
          ),
          SizedBox(height: dense ? AppDimens.space8 : AppDimens.space12),
          NexaTextField(
            controller: username,
            label: 'Username',
            hint: 'Enter your username',
            autofillHints: const [AutofillHints.username],
            prefixIcon: const Icon(Icons.person_outline_rounded),
            textInputAction: TextInputAction.next,
            focusNode: _usernameFocus,
            dense: dense,
            onFieldSubmitted: (_) =>
                FocusScope.of(context).requestFocus(_passwordFocus),
          ),
          SizedBox(height: dense ? AppDimens.space8 : AppDimens.space12),
          NexaTextField(
            controller: password,
            label: 'Password',
            hint: 'Enter your password',
            obscureText: _obscure,
            autofillHints: const [AutofillHints.password],
            prefixIcon: const Icon(Icons.lock_outline_rounded),
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
            dense: dense,
            onFieldSubmitted: (_) => submit(),
          ),
        ],
      ),
    );
  }

  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();

  Widget _submitButton() {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: AppDimens.touchTargetLarge,
      child: FilledButton(
        onPressed: loading ? null : submit,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(AppDimens.touchTargetLarge),
          shape: const StadiumBorder(),
          textStyle: AppTextStyle.labelLarge,
        ),
        child: loading
            ? SizedBox(
                width: AppDimens.iconMedium,
                height: AppDimens.iconMedium,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.onPrimary,
                ),
              )
            : const Text('Sign in'),
      ),
    );
  }

  Widget _caption() {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      'Your files stay on a server you control.',
      textAlign: TextAlign.center,
      style: AppTextStyle.bodySmall.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
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
            // Use the actual content width; MediaQuery can describe a larger window.
            final wide = constraints.maxWidth >= 700;
            final short = constraints.maxHeight < 600;
            // Keep phones edge-to-edge inside SafeArea; add gutters on wide layouts.
            final horizontal = wide ? AppDimens.pageMarginWide : 0.0;
            final vertical = short ? AppDimens.space4 : AppDimens.space32;
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
                  child: SizedBox(
                    width: constraints.maxWidth.clamp(0.0, 440.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Masthead: app mark, kept centred in the column.
                        Offstage(
                          offstage: short,
                          child: Center(child: _brandTile()),
                        ),
                        SizedBox(
                          height: short ? 0 : AppDimens.space20,
                        ),
                        _heading(short: short),
                        SizedBox(
                          height: short ? AppDimens.space8 : AppDimens.space24,
                        ),
                        SizedBox(
                          width: double.infinity,
                          child: Card(
                            color: scheme.surfaceContainerLow,
                            surfaceTintColor: Colors.transparent,
                            elevation: AppDimens.elevationSubtle,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppDimens.radiusCard,
                              ),
                            ),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: wide ? AppDimens.space20 : 0,
                                vertical:
                                    wide ? AppDimens.space20 : AppDimens.space8,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _fields(dense: short),
                                  if (error != null) ...[
                                    const SizedBox(height: AppDimens.space12),
                                    _ErrorBanner(message: error!),
                                  ],
                                  SizedBox(
                                    height: short
                                        ? AppDimens.space4
                                        : AppDimens.space16,
                                  ),
                                  _submitButton(),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Quiet footer.
                        Offstage(
                          offstage: short,
                          child: Padding(
                            padding:
                                const EdgeInsets.only(top: AppDimens.space20),
                            child: _caption(),
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
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      liveRegion: true,
      child: Card(
        color: scheme.errorContainer,
        surfaceTintColor: Colors.transparent,
        elevation: AppDimens.elevationSubtle,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusStandard),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.space12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: AppDimens.iconMedium,
                color: scheme.onErrorContainer,
              ),
              const SizedBox(width: AppDimens.space12),
              Expanded(
                child: Text(
                  message,
                  style: AppTextStyle.bodyMedium.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
