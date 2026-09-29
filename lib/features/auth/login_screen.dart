import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/storage/secure_storage.dart';
import '../../core/utils/app_logger.dart';
import '../config/client_config_service.dart';
import 'auth_service.dart';
import 'auth_state_service.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    AuthStateService().addListener(_onAuthChanged);
    if (ClientConfigService().config == null) {
      ClientConfigService().fetchClientConfig().then((_) {
        if (mounted) setState(() {});
      });
    }
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

  @override
  void dispose() {
    AuthStateService().removeListener(_onAuthChanged);
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;

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

    // Sync role/user data after login.
    await ClientConfigService().fetchClientConfig();
    AuthStateService().notifyLoggedIn();

    if (!mounted) return;

    setState(() => _loading = false);
    Navigator.of(context).pop(true);
  }

  Future<void> _clearSession() async {
    await SecureStore.clearUserSession();
    await SecureStore.clearUserRole();
    await SecureStore.clearUserId();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cleared session')));
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
      if (!result) {
        setState(() => _error = 'Could not launch social login for $target');
      }
    } catch (e) {
      AppLogger.d('[SOCIAL LOGIN] ERROR: $e');
      setState(() => _error = 'Error launching social login: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Login'),
        backgroundColor: Colors.black,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Email',
              labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.08),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Password',
              labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.08),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
                );
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.white.withValues(alpha: 0.7),
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Forgot Password?'),
            ),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Colors.redAccent.withValues(alpha: 0.95)),
              ),
            ),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Login'),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: _loading ? null : _clearSession,
            child: const Text('Clear saved session (debug)'),
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
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.5)),
                  ),
                ),
                Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.1))),
              ],
            ),
            const SizedBox(height: 16),
            Row(
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
                if (ClientConfigService().isSocialLoginActive('instagram')) ...[
                  const SizedBox(width: 12),
                  _SocialButton(
                    icon: Icons.camera_alt, // Instagram icon
                    label: 'Instagram',
                    onTap: () => _launchSocialLogin('instagram'),
                  ),
                ],
                if (ClientConfigService().isSocialLoginActive('spotify')) ...[
                  const SizedBox(width: 12),
                  _SocialButton(
                    icon: Icons.music_note, // Spotify icon
                    label: 'Spotify',
                    onTap: () => _launchSocialLogin('spotify'),
                  ),
                ],
                if (ClientConfigService().isSocialLoginActive('twitter')) ...[
                  const SizedBox(width: 12),
                  _SocialButton(
                    icon: Icons.close_rounded, // Using close as a placeholder for X
                    label: 'Twitter',
                    onTap: () => _launchSocialLogin('twitter'),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
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
