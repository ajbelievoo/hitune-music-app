import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/storage/secure_storage.dart';
import '../../core/utils/app_logger.dart';
import '../config/client_config_service.dart';
import 'auth_service.dart';
import 'auth_state_service.dart';

class AuthBottomSheet extends StatefulWidget {
  final String? reason;

  const AuthBottomSheet({super.key, this.reason});

  @override
  State<AuthBottomSheet> createState() => _AuthBottomSheetState();
}

class _AuthBottomSheetState extends State<AuthBottomSheet> with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  final _loginEmail = TextEditingController();
  final _loginPassword = TextEditingController();

  final _signupEmail = TextEditingController();
  final _signupUsername = TextEditingController();
  final _signupPassword = TextEditingController();
  final _signupPasswordRepeat = TextEditingController();

  bool _agree = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _initSocialLogins();
    AuthStateService().addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    if (!mounted) return;
    if (AuthStateService().isLoggedIn) {
      Navigator.of(context).maybePop(true);
      return;
    }
    final err = AuthStateService().takeLastError();
    if (err != null) {
      setState(() => _error = err);
    }
  }

  Future<void> _initSocialLogins() async {
    debugPrint('[AUTH_BOTTOM] initState - fetching social logins...');
    if (ClientConfigService().config == null) {
      await ClientConfigService().fetchClientConfig();
    }
    await ClientConfigService().fetchSocialLogins();
    debugPrint('[AUTH_BOTTOM] initState - social logins fetched');
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AuthStateService().removeListener(_onAuthChanged);
    _tabs.dispose();
    _loginEmail.dispose();
    _loginPassword.dispose();
    _signupEmail.dispose();
    _signupUsername.dispose();
    _signupPassword.dispose();
    _signupPasswordRepeat.dispose();
    super.dispose();
  }

  Future<void> _afterAuthSuccess() async {
    await ClientConfigService().fetchClientConfig();
    AuthStateService().notifyLoggedIn();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _submitLogin() async {
    final email = _loginEmail.text.trim();
    final password = _loginPassword.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Email and password are required');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final res = await AuthService().login(email: email, password: password);

    if (!mounted) return;

    if (!res.isSuccess) {
      setState(() {
        _loading = false;
        _error = res.error?.message ?? 'Login failed';
      });
      return;
    }

    // Try to get username from email (before @)
    final username = email.split('@').first;
    await SecureStore.setUserName(username);

    setState(() => _loading = false);
    await _afterAuthSuccess();
  }

  Future<void> _submitSignup() async {
    final email = _signupEmail.text.trim();
    final username = _signupUsername.text.trim();
    final pass = _signupPassword.text;
    final rep = _signupPasswordRepeat.text;

    if (email.isEmpty || username.isEmpty || pass.isEmpty || rep.isEmpty) {
      setState(() => _error = 'All fields are required');
      return;
    }

    if (pass != rep) {
      setState(() => _error = 'Passwords do not match');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final res = await AuthService().signup(
      email: email,
      username: username,
      password: pass,
      passwordRepeat: rep,
      agree: _agree,
    );

    if (!mounted) return;

    if (!res.isSuccess) {
      setState(() {
        _loading = false;
        _error = res.error?.message ?? 'Signup failed';
      });
      return;
    }

    // Store username after successful signup
    await SecureStore.setUserName(username);

    setState(() => _loading = false);
    await _afterAuthSuccess();
  }

  Widget _buildSocialButtons() {
    final providers = ClientConfigService().socialProviders;
    debugPrint('[AUTH_BOTTOM] _buildSocialButtons called, providers count: ${providers.length}');
    
    if (providers.isEmpty) {
      debugPrint('[AUTH_BOTTOM] No providers from API, using fallback');
      // Fallback to hardcoded if no providers fetched
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (ClientConfigService().isSocialLoginActive('google'))
            _SocialButton(
              icon: Icons.g_mobiledata,
              label: 'Google',
              onTap: () => _launchSocialLogin('google'),
            ),
          if (ClientConfigService().isSocialLoginActive('facebook')) ...[
            const SizedBox(width: 12),
            _SocialButton(
              icon: Icons.facebook,
              label: 'Facebook',
              onTap: () => _launchSocialLogin('facebook'),
            ),
          ],
          if (ClientConfigService().isSocialLoginActive('twitter')) ...[
            const SizedBox(width: 12),
            _SocialButton(
              icon: Icons.close_rounded,
              label: 'Twitter',
              onTap: () => _launchSocialLogin('twitter'),
            ),
          ],
        ],
      );
    }

    debugPrint('[AUTH_BOTTOM] Building buttons from ${providers.length} providers');
    // Build buttons from admin panel providers
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: providers.map((provider) {
        final id = provider['id']?.toString().toLowerCase() ?? '';
        final title = provider['title']?.toString() ?? 'Social';
        debugPrint('[AUTH_BOTTOM] Provider: id=$id, title=$title');
        
        IconData icon;
        switch (id) {
          case 'google':
            icon = Icons.g_mobiledata;
            break;
          case 'facebook':
            icon = Icons.facebook;
            break;
          case 'twitter':
          case 'x':
            icon = Icons.close_rounded;
            break;
          case 'apple':
            icon = Icons.apple;
            break;
          case 'linkedin':
            icon = Icons.business;
            break;
          case 'github':
            icon = Icons.code;
            break;
          case 'spotify':
            icon = Icons.music_note; // Using music note for Spotify
            break;
          default:
            icon = Icons.login;
        }
        
        return _SocialButton(
          icon: icon,
          label: title,
          onTap: () => _launchSocialLogin(id),
        );
      }).toList(),
    );
  }

  Future<void> _launchSocialLogin(String target) async {
    // Keep the user inside the app. The backend must redirect to
    // hitune://sociallogin?token=... so AppLinks can complete the login.
    final returnUri = Uri.encodeComponent('hitune://sociallogin');
    final url = Uri.parse('https://music.hitune.in/api/login_social_ini?target=$target&redirect_uri=$returnUri');
    AppLogger.d('[SOCIAL LOGIN] Launching URL: $url');

    try {
      final result = await launchUrl(
        url,
        mode: LaunchMode.inAppBrowserView,
        browserConfiguration: const BrowserConfiguration(showTitle: true),
      );
      AppLogger.d('[SOCIAL LOGIN] launchUrl result: $result');
      if (!result && mounted) {
        setState(() => _error = 'Could not launch social login for $target');
      }
    } catch (e) {
      AppLogger.d('[SOCIAL LOGIN] ERROR: $e');
      if (mounted) {
        setState(() => _error = 'Error launching social login: $e');
      }
    }
  }

  InputDecoration _dec(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.08),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenH = MediaQuery.of(context).size.height;
    final formMaxH = (screenH * 0.55).clamp(260.0, 420.0);

    // Listen to ClientConfigService changes for social providers
    return ListenableBuilder(
      listenable: ClientConfigService(),
      builder: (context, _) {
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 620),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.78),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Sign in to HiTune',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  if (widget.reason != null && widget.reason!.trim().isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      widget.reason!.trim(),
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: Colors.white.withValues(alpha: 0.70),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: _loading ? null : () => Navigator.of(context).pop(false),
                              icon: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.85)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      TabBar(
                        controller: _tabs,
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.white.withValues(alpha: 0.65),
                        indicatorColor: theme.colorScheme.primary,
                        indicatorWeight: 3,
                        tabs: const [
                          Tab(text: 'Login'),
                          Tab(text: 'Create account'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                          alignment: Alignment.topCenter,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_error != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      _error!,
                                      style: TextStyle(color: Colors.redAccent.withValues(alpha: 0.95)),
                                    ),
                                  ),
                                ),
                              ConstrainedBox(
                                constraints: BoxConstraints(maxHeight: formMaxH),
                                child: TabBarView(
                                  controller: _tabs,
                                  children: [
                                    ListView(
                                      padding: EdgeInsets.zero,
                                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                                      children: [
                                        TextField(
                                          controller: _loginEmail,
                                          keyboardType: TextInputType.emailAddress,
                                          style: const TextStyle(color: Colors.white),
                                          decoration: _dec('Email'),
                                        ),
                                        const SizedBox(height: 12),
                                        TextField(
                                          controller: _loginPassword,
                                          obscureText: true,
                                          style: const TextStyle(color: Colors.white),
                                          decoration: _dec('Password'),
                                        ),
                                        const SizedBox(height: 16),
                                        FilledButton(
                                          onPressed: _loading ? null : _submitLogin,
                                          style: FilledButton.styleFrom(
                                            minimumSize: const Size.fromHeight(48),
                                            backgroundColor: theme.colorScheme.primary,
                                          ),
                                          child: _loading
                                              ? const SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child: CircularProgressIndicator(strokeWidth: 2),
                                                )
                                              : const Text('Continue'),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Tip: You can explore Home without login. Login is only required for playback & library.',
                                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.55)),
                                        ),
                                        if (ClientConfigService().isSocialLoginEnabled) ...[
                                          const SizedBox(height: 20),
                                          Row(
                                            children: [
                                              Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.1))),
                                              Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                                child: Text(
                                                  'Or continue with',
                                                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.5)),
                                                ),
                                              ),
                                              Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.1))),
                                            ],
                                          ),
                                          const SizedBox(height: 16),
                                          _buildSocialButtons(),
                                        ],
                                      ],
                                    ),
                                    ListView(
                                      padding: EdgeInsets.zero,
                                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                                      children: [
                                        TextField(
                                          controller: _signupEmail,
                                          keyboardType: TextInputType.emailAddress,
                                          style: const TextStyle(color: Colors.white),
                                          decoration: _dec('Email'),
                                        ),
                                        const SizedBox(height: 12),
                                        TextField(
                                          controller: _signupUsername,
                                          style: const TextStyle(color: Colors.white),
                                          decoration: _dec('Username'),
                                        ),
                                        const SizedBox(height: 12),
                                        TextField(
                                          controller: _signupPassword,
                                          obscureText: true,
                                          style: const TextStyle(color: Colors.white),
                                          decoration: _dec('Password'),
                                        ),
                                        const SizedBox(height: 12),
                                        TextField(
                                          controller: _signupPasswordRepeat,
                                          obscureText: true,
                                          style: const TextStyle(color: Colors.white),
                                          decoration: _dec('Repeat password'),
                                        ),
                                        const SizedBox(height: 6),
                                        CheckboxListTile(
                                          value: _agree,
                                          onChanged: _loading ? null : (v) => setState(() => _agree = v ?? false),
                                          title: const Text('I agree to the terms', style: TextStyle(color: Colors.white)),
                                          controlAffinity: ListTileControlAffinity.leading,
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                        const SizedBox(height: 10),
                                        FilledButton(
                                          onPressed: _loading ? null : _submitSignup,
                                          style: FilledButton.styleFrom(
                                            minimumSize: const Size.fromHeight(48),
                                            backgroundColor: theme.colorScheme.primary,
                                          ),
                                          child: _loading
                                              ? const SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child: CircularProgressIndicator(strokeWidth: 2),
                                                )
                                              : const Text('Create account'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SocialButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SocialButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 72,
        height: 80,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
