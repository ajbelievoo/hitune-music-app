import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'reset_password_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final String? initialEmail;

  const ForgotPasswordScreen({super.key, this.initialEmail});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _email =
      TextEditingController(text: widget.initialEmail ?? '');

  bool _loading = false;
  String? _error;
  bool _emailSent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();

    if (email.isEmpty) {
      setState(() => _error = 'Email is required');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final res = await AuthService().forgotPassword(email: email);

    if (!mounted) return;

    if (!res.isSuccess) {
      setState(() {
        _loading = false;
        _error = res.error?.message ?? 'Failed to send reset email';
      });
      return;
    }

    setState(() {
      _loading = false;
      _emailSent = true;
    });
  }

  void _goToResetPassword() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ResetPasswordScreen(email: _email.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Forgot Password'),
        backgroundColor: Colors.black,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_emailSent) ...[
            Icon(
              Icons.check_circle_outline,
              color: Colors.greenAccent,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              'Reset email sent!',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Check your email for the verification code. If you used Google login before, you can now set a new password.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _goToResetPassword,
              child: const Text('Enter Verification Code'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => setState(() => _emailSent = false),
              child: const Text('Try different email'),
            ),
          ] else ...[
            Text(
              'Enter your email address and we\'ll send you a verification code to reset your password.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Email',
                labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
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
                  : const Text('Send Reset Code'),
            ),
          ],
        ],
      ),
    );
  }
}
