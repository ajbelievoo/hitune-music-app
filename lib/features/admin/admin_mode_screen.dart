import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/storage/secure_storage.dart';
import 'admin_auth_service.dart';
import 'client_config_admin_service.dart';

class AdminModeScreen extends StatefulWidget {
  const AdminModeScreen({super.key});

  @override
  State<AdminModeScreen> createState() => _AdminModeScreenState();
}

class _AdminModeScreenState extends State<AdminModeScreen> {
  final _svc = ClientConfigAdminService();

  final TextEditingController _pageSearch = TextEditingController();
  String _pageQuery = '';

  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _config;

  String? _csrfToken;
  bool _readOnly = false;

  bool _needsLogin = true;
  bool _checkingUserSession = true;
  bool _enableSearch = true;
  bool _enablePlaylists = true;
  bool _enableSocialLogin = true;

  bool _privateMode = false;
  bool _maintenanceMode = false;
  bool _legacySocialLogin = true;

  @override
  void initState() {
    super.initState();
    _pageSearch.addListener(() {
      final v = _pageSearch.text.trim();
      if (v == _pageQuery) return;
      if (!mounted) return;
      setState(() => _pageQuery = v);
    });
    _init();
  }

  Future<void> _init() async {
    // First check if admin already has session
    final hasAdmin = await _hasAdminSession();
    if (hasAdmin) {
      if (mounted) setState(() => _needsLogin = false);
      await _load();
      return;
    }
    
    // Check if user is logged in - if yes, use that session for admin too
    final userSessId = await SecureStore.getUserSessId();
    final userSessKey = await SecureStore.getUserSessKey();
    if (userSessId != null && userSessId.isNotEmpty && userSessKey != null && userSessKey.isNotEmpty) {
      // User is logged in, copy session to admin and load
      await SecureStore.setAdminSession(sessId: userSessId, sessKey: userSessKey);
      if (mounted) setState(() => _needsLogin = false);
      await _load();
      return;
    }
    
    // Need login - show login UI instead of loading
    if (mounted) {
      setState(() {
        _checkingUserSession = false;
        _needsLogin = true;
      });
    }
  }

  @override
  void dispose() {
    _pageSearch.dispose();
    super.dispose();
  }

  Future<void> _openPageDetails(BuildContext context, {required String key, required dynamic page}) async {
    final theme = Theme.of(context);

    String? url;
    String? title;
    String? link;
    if (page is Map) {
      final m = Map<String, dynamic>.from(page);
      url = m['url']?.toString();
      title = m['title']?.toString();
      link = m['link']?.toString();
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.70),
      builder: (ctx) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.82),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title?.isNotEmpty == true ? title! : key,
                            style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w900),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.85)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text('Key', style: theme.textTheme.labelLarge?.copyWith(color: Colors.white.withValues(alpha: 0.7))),
                    const SizedBox(height: 4),
                    SelectableText(key, style: const TextStyle(color: Colors.white)),
                    if (link != null && link.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text('Link', style: theme.textTheme.labelLarge?.copyWith(color: Colors.white.withValues(alpha: 0.7))),
                      const SizedBox(height: 4),
                      SelectableText(link, style: const TextStyle(color: Colors.white)),
                    ],
                    if (url != null && url.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text('URL regex', style: theme.textTheme.labelLarge?.copyWith(color: Colors.white.withValues(alpha: 0.7))),
                      const SizedBox(height: 4),
                      SelectableText(url, style: const TextStyle(color: Colors.white)),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: key));
                              if (!ctx.mounted) return;
                              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Copied key')));
                            },
                            icon: const Icon(Icons.copy_rounded),
                            label: const Text('Copy key'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final text = '$key${url != null ? '  ($url)' : ''}';
                              await Clipboard.setData(ClipboardData(text: text));
                              if (!ctx.mounted) return;
                              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Copied')));
                            },
                            icon: const Icon(Icons.copy_all_rounded),
                            label: const Text('Copy full'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  bool _boolFrom(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == '1' || s == 'true' || s == 'yes' || s == 'on';
    }
    return false;
  }

  Future<bool> _hasAdminSession() async {
    final id = await SecureStore.getAdminSessId();
    final key = await SecureStore.getAdminSessKey();
    return (id != null && id.isNotEmpty) && (key != null && key.isNotEmpty);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    // Final check - if still no admin session, show error
    final can = await _hasAdminSession();
    if (!can) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Admin login required';
        _needsLogin = true;
      });
      return;
    }

    final res = await _svc.getClientConfig();
    if (!mounted) return;

    if (!res.isSuccess) {
      setState(() {
        _loading = false;
        _error = res.error?.message ?? 'Failed to load admin config';
      });
      return;
    }

    final cfg = res.data!;

    String? pickToken() {
      final candidates = [
        cfg['csrf'],
        cfg['csrf_token'],
        cfg['token'],
        cfg['form_token'],
      ];
      for (final c in candidates) {
        final s = (c ?? '').toString().trim();
        if (s.isNotEmpty && s != 'null') return s;
      }
      return null;
    }

    bool pickBool(String key, {required bool fallback}) {
      if (!cfg.containsKey(key)) return fallback;
      return _boolFrom(cfg[key]);
    }

    setState(() {
      _config = cfg;
      _csrfToken = pickToken();
      _readOnly = false;
      _enableSearch = pickBool('enable_search', fallback: true);
      _enablePlaylists = pickBool('enable_playlists', fallback: true);
      _enableSocialLogin = pickBool('enable_social_login', fallback: true);

      // Some deployments expose legacy keys as well.
      _privateMode = pickBool('private', fallback: _privateMode);
      _maintenanceMode = pickBool('constructing', fallback: _maintenanceMode);
      _legacySocialLogin = pickBool('social_login', fallback: _legacySocialLogin);
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final updates = <String, String>{
      'enable_search': _enableSearch ? '1' : '0',
      'enable_playlists': _enablePlaylists ? '1' : '0',
      'enable_social_login': _enableSocialLogin ? '1' : '0',

      // Legacy keys (if backend supports them)
      'private': _privateMode ? '1' : '0',
      'constructing': _maintenanceMode ? '1' : '0',
      'social_login': _legacySocialLogin ? '1' : '0',
    };

    for (final entry in updates.entries) {
      final payload = <String, String>{
        'key': entry.key,
        'value': entry.value,
        if (_csrfToken != null && _csrfToken!.isNotEmpty) 'csrf_token': _csrfToken!,
      };
      final res = await _svc.updateClientConfig(payload);
      if (!mounted) return;
      if (!res.isSuccess) {
        final msg = res.error?.message ?? 'Save failed';
        setState(() {
          _loading = false;
          if (msg == 'Forbidden') {
            _readOnly = true;
            _error = 'Forbidden: aapke admin account ko settings update ka access nahi hai. Admin panel me permissions enable karni hongi.';
          } else {
            _error = '$msg (key=${entry.key})';
          }
        });
        return;
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Show full login UI if needs login (no background visible)
    if (_needsLogin && !_checkingUserSession) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Admin'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: _AdminLoginFullScreen(
          onLogin: () async {
            await _load();
            if (mounted && await _hasAdminSession()) {
              setState(() => _needsLogin = false);
            }
          },
          onCancel: () => Navigator.of(context).pop(),
        ),
      );
    }

    // Show loading while checking session
    if (_checkingUserSession || (_loading && _config == null)) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Admin'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFF1DB954)),
        ),
      );
    }

    final pagesNode = _config?['pages'];
    final pages = <MapEntry<String, dynamic>>[];
    if (pagesNode is Map) {
      pages.addAll(Map<String, dynamic>.from(pagesNode).entries);
    }
    pages.sort((a, b) => a.key.compareTo(b.key));

    final q = _pageQuery.trim().toLowerCase();
    final filteredPages = (q.isEmpty)
        ? pages
        : pages.where((e) {
            final key = e.key.toLowerCase();
            String title = '';
            if (e.value is Map) {
              final m = Map<String, dynamic>.from(e.value);
              title = (m['title'] ?? '').toString().toLowerCase();
            }
            return key.contains(q) || title.contains(q);
          }).toList(growable: false);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Admin Mode'),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            onPressed: _loading
                ? null
                : () async {
                    await SecureStore.clearAdminSession();
                    if (!mounted) return;
                    await _load();
                  },
            icon: const Icon(Icons.logout),
            tooltip: 'Admin logout',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Colors.redAccent.withValues(alpha: 0.95)),
              ),
            ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Core Settings', style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                SwitchListTile(
                  value: _enableSearch,
                  onChanged: (_loading || _readOnly) ? null : (v) => setState(() => _enableSearch = v),
                  title: const Text('Enable Search', style: TextStyle(color: Colors.white)),
                  subtitle: Text('Search feature on/off', style: TextStyle(color: Colors.white.withValues(alpha: 0.65))),
                ),
                SwitchListTile(
                  value: _enablePlaylists,
                  onChanged: (_loading || _readOnly) ? null : (v) => setState(() => _enablePlaylists = v),
                  title: const Text('Enable Playlists', style: TextStyle(color: Colors.white)),
                  subtitle: Text('Playlists feature on/off', style: TextStyle(color: Colors.white.withValues(alpha: 0.65))),
                ),
                SwitchListTile(
                  value: _enableSocialLogin,
                  onChanged: (_loading || _readOnly) ? null : (v) => setState(() => _enableSocialLogin = v),
                  title: const Text('Enable Social Login', style: TextStyle(color: Colors.white)),
                  subtitle: Text('Google/Facebook login on/off', style: TextStyle(color: Colors.white.withValues(alpha: 0.65))),
                ),
                const Divider(height: 18),
                Text('App Modes', style: theme.textTheme.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                SwitchListTile(
                  value: _privateMode,
                  onChanged: (_loading || _readOnly) ? null : (v) => setState(() => _privateMode = v),
                  title: const Text('Private mode', style: TextStyle(color: Colors.white)),
                  subtitle: Text('Restrict app access', style: TextStyle(color: Colors.white.withValues(alpha: 0.65))),
                ),
                SwitchListTile(
                  value: _maintenanceMode,
                  onChanged: (_loading || _readOnly) ? null : (v) => setState(() => _maintenanceMode = v),
                  title: const Text('Maintenance', style: TextStyle(color: Colors.white)),
                  subtitle: Text('Show constructing mode', style: TextStyle(color: Colors.white.withValues(alpha: 0.65))),
                ),
                SwitchListTile(
                  value: _legacySocialLogin,
                  onChanged: (_loading || _readOnly) ? null : (v) => setState(() => _legacySocialLogin = v),
                  title: const Text('Social login (legacy)', style: TextStyle(color: Colors.white)),
                  subtitle: Text('Old key: social_login', style: TextStyle(color: Colors.white.withValues(alpha: 0.65))),
                ),
                const SizedBox(height: 10),
                if (!_readOnly)
                  FilledButton(
                    onPressed: _loading ? null : _save,
                    child: _loading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save changes'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (pages.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  collapsedBackgroundColor: Colors.white.withValues(alpha: 0.06),
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  collapsedShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  iconColor: Colors.white.withValues(alpha: 0.8),
                  collapsedIconColor: Colors.white.withValues(alpha: 0.8),
                  title: Text(
                    'Admin Pages',
                    style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                      child: TextField(
                        controller: _pageSearch,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Search pages…',
                          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
                          prefixIcon: const Icon(Icons.search_rounded),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.07),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    if (filteredPages.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                        child: Text('No pages found', style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
                      ),
                    for (final e in filteredPages)
                      Builder(
                        builder: (context) {
                          final key = e.key;
                          final v = e.value;
                          String? url;
                          String? title;
                          String? link;
                          if (v is Map) {
                            final m = Map<String, dynamic>.from(v);
                            url = m['url']?.toString();
                            title = m['title']?.toString();
                            link = m['link']?.toString();
                          }
                          return ListTile(
                            dense: true,
                            title: Text(title?.isNotEmpty == true ? title! : key, style: const TextStyle(color: Colors.white)),
                            subtitle: Text(url ?? '', style: TextStyle(color: Colors.white.withValues(alpha: 0.65))),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  onPressed: () => _openPageDetails(context, key: key, page: v),
                                  icon: Icon(Icons.open_in_new_rounded, color: Colors.white.withValues(alpha: 0.8)),
                                  tooltip: 'Details',
                                ),
                                IconButton(
                                  onPressed: () async {
                                    final data = '$key${link != null && link.isNotEmpty ? '  ($link)' : ''}${url != null ? '  ($url)' : ''}';
                                    await Clipboard.setData(ClipboardData(text: data));
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                                  },
                                  icon: Icon(Icons.copy_rounded, color: Colors.white.withValues(alpha: 0.8)),
                                  tooltip: 'Copy',
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                collapsedBackgroundColor: Colors.white.withValues(alpha: 0.06),
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                collapsedShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                ),
                iconColor: Colors.white.withValues(alpha: 0.8),
                collapsedIconColor: Colors.white.withValues(alpha: 0.8),
                title: Text(
                  'Raw client_config',
                  style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                children: [
                  const SizedBox(height: 8),
                  Text(
                    _config == null ? 'Not loaded' : const JsonEncoder.withIndent('  ').convert(_config),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 90),
        ],
      ),
    );
  }
}

class _AdminLoginFullScreen extends StatefulWidget {
  final VoidCallback onLogin;
  final VoidCallback onCancel;

  const _AdminLoginFullScreen({required this.onLogin, required this.onCancel});

  @override
  State<_AdminLoginFullScreen> createState() => _AdminLoginFullScreenState();
}

class _AdminLoginFullScreenState extends State<_AdminLoginFullScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final pass = _password.text;

    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Email aur password required hai');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final res = await AdminAuthService().login(email: email, password: pass);
    if (!mounted) return;

    if (!res.isSuccess) {
      setState(() {
        _loading = false;
        _error = res.error?.message ?? 'Admin login fail';
      });
      return;
    }

    setState(() => _loading = false);
    widget.onLogin();
  }

  InputDecoration _dec(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.08),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Admin Login',
            style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            'Admin access ke liye login karein',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 24),
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_error!, style: TextStyle(color: Colors.redAccent.withValues(alpha: 0.95))),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: Colors.white),
            decoration: _dec('Email'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            style: const TextStyle(color: Colors.white),
            decoration: _dec('Password'),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _loading ? null : _submit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: const Color(0xFF1DB954),
              ),
              child: _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Text('Continue', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: widget.onCancel,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: Colors.white,
              ),
              child: const Text('Back'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminLoginSheet extends StatefulWidget {
  const _AdminLoginSheet();

  @override
  State<_AdminLoginSheet> createState() => _AdminLoginSheetState();
}

class _AdminLoginSheetState extends State<_AdminLoginSheet> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final pass = _password.text;

    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Email aur password required hai');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final res = await AdminAuthService().login(email: email, password: pass);
    if (!mounted) return;

    if (!res.isSuccess) {
      setState(() {
        _loading = false;
        _error = res.error?.message ?? 'Admin login fail';
      });
      return;
    }

    setState(() => _loading = false);
    Navigator.of(context).pop(true);
  }

  InputDecoration _dec(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.08),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.82),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Admin Login',
                              style: theme.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w900),
                            ),
                          ),
                          IconButton(
                            onPressed: _loading ? null : () => Navigator.of(context).pop(false),
                            icon: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.85)),
                          ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(_error!, style: TextStyle(color: Colors.redAccent.withValues(alpha: 0.95))),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: Colors.white),
                        decoration: _dec('Email'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _password,
                        obscureText: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: _dec('Password'),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _loading ? null : _submit,
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        child: _loading
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Continue'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
