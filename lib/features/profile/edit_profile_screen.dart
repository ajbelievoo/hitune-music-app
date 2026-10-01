import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/storage/secure_storage.dart';
import '../auth/forgot_password_screen.dart';
import 'add_funds_dialog.dart';
import 'user_edit_service.dart';

class EditProfileScreen extends StatefulWidget {
  final int initialTabIndex;
  
  const EditProfileScreen({super.key, this.initialTabIndex = 0});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> with SingleTickerProviderStateMixin {
  final _svc = UserEditService();
  late TabController _tabCtrl;

  // Profile fields
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  String? _currentAvatar;
  String? _currentCover;
  File? _newAvatar;
  File? _newCover;

  // Security fields
  final _oldPassCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _repeatPassCtrl = TextEditingController();
  bool _socialLoginEnabled = true;

  // Links fields
  final _facebookCtrl = TextEditingController();
  final _xCtrl = TextEditingController();
  final _linkedinCtrl = TextEditingController();
  final _spotifyCtrl = TextEditingController();
  final _soundcloudCtrl = TextEditingController();
  final _youtubeCtrl = TextEditingController();

  // Delete account
  final _deletePassCtrl = TextEditingController();
  bool _deleteConfirmed = false;

  // Notifications
  Map<String, dynamic> _notificationInputs = {};
  Map<String, bool> _notificationValues = {};
  bool _emailNotifications = true;

  // Sessions
  List<dynamic> _sessions = [];


  /* ---- theme-aware palette (screen follows app light/dark theme) ---- */
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _bg => _isDark ? Colors.black : const Color(0xFFF7F7F9);
  Color get _surface => _isDark ? const Color(0xFF1C1C22) : Colors.white;
  Color get _cardBg => _isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04);
  Color get _cardBg2 => _isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.03);
  Color get _border => _isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.12);
  Color get _fg => _isDark ? Colors.white : const Color(0xFF101018);
  Color get _fgSub => _isDark ? Colors.white.withValues(alpha: 0.6) : Colors.black.withValues(alpha: 0.62);
  Color get _fgMid => _isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.45);

  // Transactions
  Map<String, dynamic>? _transactionData;

  bool _loading = true;
  String? _error;
  String _activeTab = 'profile';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 7, vsync: this, initialIndex: widget.initialTabIndex);
    _tabCtrl.addListener(_onTabChanged);
    final tabs = ['profile', 'security', 'transactions', 'notifications', 'links', 'sessions', 'delete'];
    _loadTab(tabs[widget.initialTabIndex]);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _tabCtrl.removeListener(_onTabChanged);
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _bioCtrl.dispose();
    _oldPassCtrl.dispose();
    _newPassCtrl.dispose();
    _repeatPassCtrl.dispose();
    _facebookCtrl.dispose();
    _xCtrl.dispose();
    _linkedinCtrl.dispose();
    _spotifyCtrl.dispose();
    _soundcloudCtrl.dispose();
    _youtubeCtrl.dispose();
    _deletePassCtrl.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabCtrl.indexIsChanging) {
      final tabs = ['profile', 'security', 'transactions', 'notifications', 'links', 'sessions', 'delete'];
      if (_tabCtrl.index < tabs.length) {
        _loadTab(tabs[_tabCtrl.index]);
      }
    }
  }

  Future<void> _loadTab(String tab) async {
    if (!mounted) return;
    
    setState(() {
      _loading = true;
      _error = null;
      _activeTab = tab;
    });

    final res = await _svc.fetchTab(tab: tab);
    if (!mounted) return;

    if (!res.isSuccess || res.data == null) {
      // Check for 403/session expired
      final errorMsg = res.error?.message ?? '';
      final is403 = errorMsg.contains('403') || res.error?.code == '403';
      
      setState(() {
        _loading = false;
        _error = is403 ? 'Session expired. Please login again.' : (res.error?.message ?? 'Failed to load $tab');
      });
      
      // If 403, show session expired dialog after a short delay
      if (is403 && mounted) {
        Future.delayed(const Duration(milliseconds: 100), () {
          _showSessionExpiredDialog();
        });
      }
      return;
    }

    final data = res.data!;
    debugPrint('[EDIT_PROFILE] API Response data keys: ${data.keys.toList()}');
    
    // Parse bofForm inputs if available
    final bofForm = data['bofForm'];
    debugPrint('[EDIT_PROFILE] bofForm type: ${bofForm.runtimeType}');
    if (bofForm is Map) {
      debugPrint('[EDIT_PROFILE] bofForm inputs keys: ${bofForm['inputs']?.keys?.toList()}');
      _parseInputs(bofForm, tab);
    }

    // Also check for user object (avatar may be here)
    final user = data['user'];
    debugPrint('[EDIT_PROFILE] user object type: ${user.runtimeType}');
    if (user is Map && tab == 'profile') {
      debugPrint('[EDIT_PROFILE] Found user object, user keys: ${user.keys.toList()}');
      
      // Get EMAIL from user object first
      final email = user['email']?.toString();
      if (email != null && email.isNotEmpty) {
        setState(() => _emailCtrl.text = email);
        debugPrint('[EDIT_PROFILE] Set email from user object: $email');
      }
      
      debugPrint('[EDIT_PROFILE] user[avatar]: ${user['avatar']}');
      debugPrint('[EDIT_PROFILE] user[avatar_url]: ${user['avatar_url']}');
      debugPrint('[EDIT_PROFILE] user[photo]: ${user['photo']}');
      
      // Try to get avatar from user object - handle Map with path field
      String? avatarUrl;
      if (user['avatar_url'] != null) {
        avatarUrl = user['avatar_url']?.toString();
        debugPrint('[EDIT_PROFILE] Got avatar from avatar_url: $avatarUrl');
      } else if (user['avatar'] is Map) {
        final avatarMap = user['avatar'] as Map;
        final path = avatarMap['path']?.toString();
        debugPrint('[EDIT_PROFILE] avatarMap[path]: $path');
        if (path != null && path.isNotEmpty) {
          avatarUrl = 'https://music.hitune.in/$path';
          debugPrint('[EDIT_PROFILE] Got avatar from avatar.path: $avatarUrl');
        }
      } else if (user['avatar'] != null) {
        avatarUrl = user['avatar']?.toString();
        debugPrint('[EDIT_PROFILE] Got avatar from avatar (string): $avatarUrl');
      } else if (user['photo'] != null) {
        avatarUrl = user['photo']?.toString();
        debugPrint('[EDIT_PROFILE] Got avatar from photo: $avatarUrl');
      }
      
      if (avatarUrl != null && avatarUrl.isNotEmpty) {
        setState(() => _currentAvatar = avatarUrl);
        await SecureStore.setUserAvatar(avatarUrl);
        debugPrint('[EDIT_PROFILE] Set _currentAvatar from user object to: $_currentAvatar');
        if (mounted) {
          setState(() {});
          debugPrint('[EDIT_PROFILE] setState called after avatar update');
        }
      } else {
        debugPrint('[EDIT_PROFILE] No avatarUrl found from user object');
      }
      
      // Also get COVER from user object
      String? coverUrl;
      if (user['cover_url'] != null) {
        coverUrl = user['cover_url']?.toString();
        debugPrint('[EDIT_PROFILE] Got cover from cover_url: $coverUrl');
      } else if (user['cover'] is Map) {
        final coverMap = user['cover'] as Map;
        final path = coverMap['path']?.toString();
        debugPrint('[EDIT_PROFILE] coverMap[path]: $path');
        if (path != null && path.isNotEmpty) {
          coverUrl = 'https://music.hitune.in/$path';
          debugPrint('[EDIT_PROFILE] Got cover from cover.path: $coverUrl');
        }
      } else if (user['cover'] != null) {
        coverUrl = user['cover']?.toString();
        debugPrint('[EDIT_PROFILE] Got cover from cover (string): $coverUrl');
      } else if (user['cover_photo'] != null) {
        coverUrl = user['cover_photo']?.toString();
        debugPrint('[EDIT_PROFILE] Got cover from cover_photo: $coverUrl');
      }
      
      if (coverUrl != null && coverUrl.isNotEmpty) {
        setState(() => _currentCover = coverUrl);
        await SecureStore.setUserCover(coverUrl);
        debugPrint('[EDIT_PROFILE] Set _currentCover from user object to: $_currentCover');
        if (mounted) {
          setState(() {});
          debugPrint('[EDIT_PROFILE] setState called after cover update');
        }
      } else {
        debugPrint('[EDIT_PROFILE] No coverUrl found from user object');
      }
    }

    // Parse content for sessions/transactions
    final content = data['content'];
    if (content is Map<String, dynamic>) {
      if (tab == 'sessions') {
        // Backend sends HTML content for sessions - parse it
        final html = content['html']?.toString() ?? '';
        _sessions = _parseSessionsHtml(html);
      } else if (tab == 'transactions') {
        // Backend sends HTML content, parse it
        final html = content['html']?.toString() ?? '';
        _transactionData = _parseTransactionHtml(html);
      }
    }

    setState(() => _loading = false);
  }

  // bofForm wraps each field as {label, tip, input: {type, name, value}} —
  // the actual value lives one level down inside `input`.
  dynamic _inputValue(Map wrapper) {
    final inner = wrapper['input'];
    if (inner is Map && inner.containsKey('value')) return inner['value'];
    return wrapper['value'];
  }

  bool _inputBool(Map wrapper) {
    final v = _inputValue(wrapper);
    return v == true || v == 1 || v == '1' || v == 'true' || v == 'on';
  }

  void _parseInputs(Map bofForm, String tab) {
    final inputs = bofForm['inputs'];
    if (inputs is! Map) return;

    switch (tab) {
      case 'profile':
        final nameInput = inputs['name'];
        if (nameInput is Map) {
          _nameCtrl.text = _inputValue(nameInput)?.toString() ?? '';
        }
        final bioInput = inputs['bio'];
        if (bioInput is Map) {
          _bioCtrl.text = _inputValue(bioInput)?.toString() ?? '';
        }
        final avatarInput = inputs['avatar_id'];
        if (avatarInput is Map) {
          final avatarId = _inputValue(avatarInput)?.toString();
          if (avatarId != null && avatarId.isNotEmpty) {
            _currentAvatar = _buildImageUrl(avatarId, 'avatar');
          }
        }
        final coverInput = inputs['bg_img_id'];
        if (coverInput is Map) {
          final coverId = _inputValue(coverInput)?.toString();
          if (coverId != null && coverId.isNotEmpty) {
            _currentCover = _buildImageUrl(coverId, 'cover');
          }
        }
        // Also get from SecureStore as fallback
        _loadFromStorage();
        break;
      case 'security':
        final emailInput = inputs['email'];
        if (emailInput is Map) {
          final v = _inputValue(emailInput)?.toString();
          if (v != null && v.isNotEmpty) _emailCtrl.text = v;
        }
        final socialInput = inputs['social_login'];
        if (socialInput is Map) {
          _socialLoginEnabled = _inputBool(socialInput);
        }
        break;
      case 'links':
        _setLinkInput(inputs, 'facebook', _facebookCtrl);
        _setLinkInput(inputs, 'x', _xCtrl);
        _setLinkInput(inputs, 'linkedin', _linkedinCtrl);
        _setLinkInput(inputs, 'spotify', _spotifyCtrl);
        _setLinkInput(inputs, 'soundcloud', _soundcloudCtrl);
        _setLinkInput(inputs, 'youtube', _youtubeCtrl);
        break;
      case 'notifications':
        _notificationInputs = {};
        _notificationValues = {};
        for (final key in inputs.keys) {
          final notifInput = inputs[key];
          if (notifInput is! Map) continue;
          if (key == '__email__') {
            _emailNotifications = _inputBool(notifInput);
          } else {
            _notificationInputs[key] = notifInput;
            _notificationValues[key] = _inputBool(notifInput);
          }
        }
        break;
    }
  }

  Future<void> _loadFromStorage() async {
    final storedName = await SecureStore.getUserName();
    final storedAvatar = await SecureStore.getUserAvatar();
    final storedCover = await SecureStore.getUserCover();
    
    if (storedName != null && storedName.isNotEmpty && _nameCtrl.text.isEmpty) {
      _nameCtrl.text = storedName;
    }
    if (storedAvatar != null && storedAvatar.isNotEmpty && (_currentAvatar == null || _currentAvatar!.isEmpty)) {
      _currentAvatar = storedAvatar;
    }
    if (storedCover != null && storedCover.isNotEmpty && (_currentCover == null || _currentCover!.isEmpty)) {
      _currentCover = storedCover;
    }
  }

  void _setLinkInput(Map inputs, String key, TextEditingController ctrl) {
    final input = inputs[key];
    if (input is Map) {
      ctrl.text = _inputValue(input)?.toString() ?? '';
    }
  }

  String _buildImageUrl(String id, String type) {
    return 'https://music.hitune.in/files/$id';
  }

  Future<void> _pickAvatar() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
    );
    if (res == null || res.files.isEmpty) return;
    final path = res.files.single.path;
    if (path == null || path.isEmpty) return;
    setState(() => _newAvatar = File(path));
  }

  Future<void> _pickCover() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
    );
    if (res == null || res.files.isEmpty) return;
    final path = res.files.single.path;
    if (path == null || path.isEmpty) return;
    setState(() => _newCover = File(path));
  }

  Future<void> _submitProfile() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showError('Name is required');
      return;
    }

    debugPrint('[EDIT_PROFILE] Starting profile submission...');
    debugPrint('[EDIT_PROFILE] Name: $name, NewAvatar: ${_newAvatar != null}, NewCover: ${_newCover != null}');

    setState(() => _loading = true);

    String? avatarId;
    String? coverId;

    if (_newAvatar != null) {
      debugPrint('[EDIT_PROFILE] Uploading avatar...');
      final upRes = await _svc.uploadAvatar(filePath: _newAvatar!.path);
      debugPrint('[EDIT_PROFILE] Avatar upload result: isSuccess=${upRes.isSuccess}, data=${upRes.data}, error=${upRes.error?.message}');
      if (!upRes.isSuccess) {
        setState(() => _loading = false);
        _showError('Avatar upload failed: ${upRes.error?.message}');
        return;
      }
      avatarId = upRes.data;
      debugPrint('[EDIT_PROFILE] Avatar ID received: $avatarId');
    }

    if (_newCover != null) {
      debugPrint('[EDIT_PROFILE] Uploading cover...');
      final upRes = await _svc.uploadCover(filePath: _newCover!.path);
      debugPrint('[EDIT_PROFILE] Cover upload result: isSuccess=${upRes.isSuccess}, data=${upRes.data}');
      if (!upRes.isSuccess) {
        setState(() => _loading = false);
        _showError('Cover upload failed: ${upRes.error?.message}');
        return;
      }
      coverId = upRes.data;
    }

    debugPrint('[EDIT_PROFILE] Submitting profile with bio=${_bioCtrl.text}');
    final res = await _svc.submitProfile(name: name, bio: _bioCtrl.text.trim(), avatarId: avatarId, coverId: coverId);
    debugPrint('[EDIT_PROFILE] Submit profile result: isSuccess=${res.isSuccess}, error=${res.error?.message}');
    
    if (!mounted) return;
    setState(() => _loading = false);

    if (!res.isSuccess) {
      _showError('Save failed: ${res.error?.message}');
      return;
    }

    // Update SecureStore with new data
    await SecureStore.setUserName(name);
    if (_newAvatar != null && avatarId != null) {
      final avatarUrl = _buildImageUrl(avatarId, 'avatar');
      debugPrint('[EDIT_PROFILE] Saving avatar URL to storage: $avatarUrl');
      await SecureStore.setUserAvatar(avatarUrl);
    }
    if (_newCover != null && coverId != null) {
      final coverUrl = _buildImageUrl(coverId, 'cover');
      await SecureStore.setUserCover(coverUrl);
    }

    _showSuccess('Profile updated!');
    Navigator.of(context).pop(true);
  }

  Future<void> _submitSecurity() async {
    final oldPass = _oldPassCtrl.text;
    final newPass = _newPassCtrl.text;
    final repeatPass = _repeatPassCtrl.text;

    if (oldPass.isEmpty) {
      _showError('Old password is required');
      return;
    }

    if (newPass.isNotEmpty && newPass != repeatPass) {
      _showError('New passwords do not match');
      return;
    }

    setState(() => _loading = true);

    final res = await _svc.submitSecurity(
      oldPassword: oldPass,
      newPassword: newPass.isEmpty ? null : newPass,
      socialLoginEnabled: _socialLoginEnabled,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (!res.isSuccess) {
      _showError('Update failed: ${res.error?.message}');
      return;
    }

    _oldPassCtrl.clear();
    _newPassCtrl.clear();
    _repeatPassCtrl.clear();
    _showSuccess('Security settings updated!');
  }

  Future<void> _submitLinks() async {
    setState(() => _loading = true);

    final links = {
      'facebook': _facebookCtrl.text.trim(),
      'x': _xCtrl.text.trim(),
      'linkedin': _linkedinCtrl.text.trim(),
      'spotify': _spotifyCtrl.text.trim(),
      'soundcloud': _soundcloudCtrl.text.trim(),
      'youtube': _youtubeCtrl.text.trim(),
    };

    final res = await _svc.submitLinks(links: links);

    if (!mounted) return;
    setState(() => _loading = false);

    if (!res.isSuccess) {
      _showError('Update failed: ${res.error?.message}');
      return;
    }

    _showSuccess('Social links updated!');
  }

  Future<void> _submitNotifications() async {
    setState(() => _loading = true);

    final values = <String, bool>{};
    for (final key in _notificationValues.keys) {
      values[key] = _notificationValues[key] ?? false;
    }

    debugPrint('[NOTIFICATIONS_SUBMIT] Sending values: $values');
    debugPrint('[NOTIFICATIONS_SUBMIT] Email notifications: $_emailNotifications');
    
    final res = await _svc.submitNotifications(
      notifications: values,
      emailNotifications: _emailNotifications,
    );
    
    debugPrint('[NOTIFICATIONS_SUBMIT] Response: isSuccess=${res.isSuccess}, error=${res.error?.message}');

    if (!mounted) return;
    setState(() => _loading = false);

    if (!res.isSuccess) {
      _showError('Update failed: ${res.error?.message}');
      return;
    }

    _showSuccess('Notification preferences saved!');
    // Re-sync toggles with what the server actually stored.
    await _loadTab('notifications');
  }

  Future<void> _submitDelete() async {
    if (!_deleteConfirmed) {
      _showError('Please confirm account deletion');
      return;
    }

    final password = _deletePassCtrl.text;
    if (password.isEmpty) {
      _showError('Password is required');
      return;
    }

    setState(() => _loading = true);

    final res = await _svc.submitDelete(password: password);

    if (!mounted) return;
    setState(() => _loading = false);

    if (!res.isSuccess) {
      _showError('Delete failed: ${res.error?.message}');
      return;
    }

    // Clear all user data
    await SecureStore.clearUserName();
    await SecureStore.clearUserAvatar();
    await SecureStore.clearUserCover();
    
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _revokeSession(String sessionId) async {
    setState(() => _loading = true);

    final res = await _svc.revokeSession(sessionId: sessionId);

    if (!mounted) return;

    if (res.isSuccess) {
      await _loadTab('sessions');
    } else {
      setState(() => _loading = false);
      _showError('Failed to revoke session: ${res.error?.message}');
    }
  }

  Map<String, dynamic> _parseTransactionHtml(String html) {
    // Extract funds from HTML - backend sends: <div class='_p'>$123.45</div>
    final fundsMatch = RegExp(r"class='_p'>\s*([^<]+)<").firstMatch(html);
    final fundsText = fundsMatch?.group(1)?.trim() ?? '0';
    final funds = double.tryParse(fundsText.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0;

    // Extract transactions from HTML
    final transactions = <Map<String, dynamic>>[];
    final transactionMatches = RegExp(r"<div class='transaction[^']*'>([\s\S]*?)</div>\s*</div>").allMatches(html);
    
    for (final match in transactionMatches) {
      final chunk = match.group(1) ?? '';
      final type = RegExp(r"class='_type'>([^<]+)<").firstMatch(chunk)?.group(1)?.trim();
      final amount = RegExp(r"class='_amount'><b>([^<]+)<").firstMatch(chunk)?.group(1)?.trim();
      final currency = RegExp(r"</b>\s*([^<]+)<").firstMatch(chunk)?.group(1)?.trim();
      final title = RegExp(r"class='_ci'>\s*<b>([^<]+)<").firstMatch(chunk)?.group(1)?.trim();
      
      if (type != null && amount != null) {
        transactions.add({
          'type': type,
          'amount': amount,
          'currency': currency ?? 'USD',
          'title': title ?? '',
        });
      }
    }

    return {
      'funds': funds,
      'transactions': transactions,
    };
  }

  List<Map<String, dynamic>> _parseSessionsHtml(String html) {
    final sessions = <Map<String, dynamic>>[];
    // Backend sends HTML table rows for sessions. Attribute quotes can be
    // single or double — keep every pattern quote-agnostic.
    final rowMatches = RegExp(r'''<tr class=["']session[^"']*["']>([\s\S]*?)</tr>''').allMatches(html);

    String stripTags(String s) =>
        s.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

    for (final match in rowMatches) {
      final chunk = match.group(1) ?? '';

      // Fallback: all <td> cell texts, so unknown markup still shows data.
      final cells = RegExp(r'''<td[^>]*>([\s\S]*?)</td>''')
          .allMatches(chunk)
          .map((e) => stripTags(e.group(1) ?? ''))
          .where((e) => e.isNotEmpty)
          .toList();

      // Extract IP — prefer classed cells, else any IPv4 in the row.
      var ip = RegExp(r'''class=["']ip["']><span>([^<]+)<''').firstMatch(chunk)?.group(1)?.trim() ??
               RegExp(r'''<td class=["']ip["']>([^<]+)<''').firstMatch(chunk)?.group(1)?.trim() ??
               RegExp(r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}').firstMatch(chunk)?.group(0) ??
               'Unknown';

      // Extract platform
      var platform = RegExp(r'''<td class=["']platform["']>([^<]+)<''').firstMatch(chunk)?.group(1)?.trim() ?? '';

      // Extract OS - usually second platform td
      final platformMatches = RegExp(r'''<td class=["']platform["']>([^<]+)<''').allMatches(chunk);
      var os = platformMatches.length > 1 ? platformMatches.elementAt(1).group(1)?.trim() ?? '' : '';

      // Extract browser - usually third platform td
      var browser = platformMatches.length > 2 ? platformMatches.elementAt(2).group(1)?.trim() ?? '' : '';

      // Extract last seen time
      var lastSeen = RegExp(r'''class=["']time_online["']>([^<]+)<''').firstMatch(chunk)?.group(1)?.trim() ?? '';

      // Positional fallback when the class names don't match the markup.
      if (platform.isEmpty && cells.length > 1) platform = cells[1];
      if (os.isEmpty && cells.length > 2) os = cells[2];
      if (browser.isEmpty && cells.length > 3) browser = cells[3];
      if (lastSeen.isEmpty && cells.isNotEmpty) lastSeen = cells.last;
      if (ip == 'Unknown' && cells.isNotEmpty) ip = cells.first;

      // Check if current session (has 'this' class or 'YOU' badge)
      final isCurrent = chunk.contains('class="this"') || chunk.contains("class='this'") || chunk.contains('<b>YOU</b>');

      // Extract session ID for revoke
      final sessionId = RegExp(r'''data-sess-id=["']([^"']+)["']''').firstMatch(chunk)?.group(1) ?? '';

      // Extract country from flag image — any flag-URL shape.
      final country = RegExp(r'flagsapi\.com/([A-Za-z]{2})/').firstMatch(chunk)?.group(1)?.toUpperCase() ??
                      RegExp(r'flags?/([A-Za-z]{2})\.').firstMatch(chunk)?.group(1)?.toUpperCase() ??
                      RegExp(r'/([A-Z]{2})\.png').firstMatch(chunk)?.group(1) ??
                      '_U';
      
      sessions.add({
        'ip': ip,
        'platform_type': platform,
        'os': os,
        'browser': browser,
        'time_online': lastSeen,
        'is_current': isCurrent,
        'session_id': sessionId,
        'ip_country': country,
      });
    }
    
    return sessions;
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.green),
    );
  }

  void _showSessionExpiredDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        title: Text('Session Expired', style: TextStyle(color: _fg)),
        content: Text(
          'Your session has expired. Please login again to continue.',
          style: TextStyle(color: _fgSub),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop(); // Close EditProfileScreen
            },
            child: const Text('OK', style: TextStyle(color: Colors.blueAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: _bg,
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          labelColor: _fg,
          unselectedLabelColor: _fgMid,
          indicatorColor: Colors.blueAccent,
          tabs: const [
            Tab(text: 'Profile'),
            Tab(text: 'Security'),
            Tab(text: 'Wallet'),
            Tab(text: 'Notifications'),
            Tab(text: 'Links'),
            Tab(text: 'Sessions'),
            Tab(text: 'Delete'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildProfileTab(),
          _buildSecurityTab(),
          _buildTransactionsTab(),
          _buildNotificationsTab(),
          _buildLinksTab(),
          _buildSessionsTab(),
          _buildDeleteTab(),
        ],
      ),
    );
  }

  Widget _buildProfileTab() {
    if (_loading && _nameCtrl.text.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _nameCtrl.text.isEmpty) {
      return _buildErrorView();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCoverSection(),
          const SizedBox(height: 20),
          Center(child: _buildAvatarSection()),
          const SizedBox(height: 24),
          _buildTextField(controller: _nameCtrl, label: 'Display Name', hint: 'Your display name', icon: Icons.person_outline),
          const SizedBox(height: 16),
          _buildTextField(controller: _bioCtrl, label: 'Bio', hint: 'Tell us about yourself', icon: Icons.description_outlined, maxLines: 3),
          const SizedBox(height: 16),
          _buildTextField(controller: _emailCtrl, label: 'Email', hint: 'Your email', icon: Icons.email_outlined, enabled: false),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _loading ? null : _submitProfile,
              icon: _loading ? SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _fg)) : Icon(Icons.save),
              label: Text(_loading ? 'Saving...' : 'Save Profile'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blueAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Change Password'),
          const SizedBox(height: 16),
          _buildTextField(controller: _oldPassCtrl, label: 'Old Password', hint: 'Enter current password', icon: Icons.lock_outline, obscure: true),
          const SizedBox(height: 12),
          _buildTextField(controller: _newPassCtrl, label: 'New Password', hint: 'Enter new password', icon: Icons.lock_outline, obscure: true),
          const SizedBox(height: 12),
          _buildTextField(controller: _repeatPassCtrl, label: 'Repeat New Password', hint: 'Confirm new password', icon: Icons.lock_outline, obscure: true),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ForgotPasswordScreen(initialEmail: _emailCtrl.text.trim()),
                ));
              },
              icon: const Icon(Icons.help_outline, size: 18, color: Colors.blueAccent),
              label: const Text(
                'Signed up with Google? Set a password via Forgot Password',
                style: TextStyle(color: Colors.blueAccent, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildSectionTitle('Social Login'),
          SwitchListTile(
            title: Text('Enable Social Login', style: TextStyle(color: _fg)),
            subtitle: Text('Allow social login with same email', style: TextStyle(color: _fgSub, fontSize: 12)),
            value: _socialLoginEnabled,
            onChanged: (v) => setState(() => _socialLoginEnabled = v),
            activeColor: Colors.blueAccent,
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _loading ? null : _submitSecurity,
              icon: _loading ? SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _fg)) : Icon(Icons.save),
              label: Text(_loading ? 'Saving...' : 'Save Security Settings'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blueAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final funds = _transactionData?['funds'] ?? 0.0;
    final transactions = _transactionData?['transactions'] ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet, color: Colors.greenAccent, size: 40),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your Funds', style: TextStyle(color: _fgSub, fontSize: 14)),
                      Text('\$${funds.toStringAsFixed(2)}', style: TextStyle(color: _fg, fontSize: 28, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: () async {
                    await showDialog(
                      context: context,
                      builder: (context) => const AddFundsDialog(),
                    );
                    // Refresh transactions after dialog closes
                    await _loadTab('transactions');
                  },
                  style: FilledButton.styleFrom(backgroundColor: Colors.blueAccent),
                  child: const Text('Add Funds'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle('Transaction History'),
          const SizedBox(height: 12),
          if (transactions.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('No transactions yet', style: TextStyle(color: _fgMid)),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: transactions.length,
              itemBuilder: (ctx, i) => _buildTransactionItem(transactions[i]),
            ),
        ],
      ),
    );
  }

  Widget _buildTransactionItem(Map txn) {
    final type = txn['type'] ?? 'unknown';
    final amount = txn['amount'] ?? 0;
    final currency = txn['currency'] ?? 'USD';
    final item = txn['object_item'];
    
    // Parse amount to number for comparison
    final amountNum = double.tryParse(amount.toString().replaceAll(RegExp(r'[^0-9.-]'), '')) ?? 0;
    final isPositive = amountNum > 0;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          if (item != null && item['cover'] != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                item['cover']['image_thumb'] ?? '',
                width: 50,
                height: 50,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(width: 50, height: 50, color: Colors.grey[800]),
              ),
            )
          else
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.music_note, color: _fgMid),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(type.toUpperCase(), style: TextStyle(color: _fgSub, fontSize: 12)),
                if (item != null)
                  Text(item['title'] ?? 'Unknown', style: TextStyle(color: _fg, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Text(
            '${isPositive ? '+' : ''}$amount $currency',
            style: TextStyle(
              color: isPositive ? Colors.greenAccent : Colors.redAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationsTab() {
    if (_loading && _notificationInputs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Email Notifications'),
          SwitchListTile(
            title: Text('Enable email notifications', style: TextStyle(color: _fg)),
            subtitle: Text('Receive notifications via email', style: TextStyle(color: _fgSub, fontSize: 12)),
            value: _emailNotifications,
            onChanged: (v) => setState(() => _emailNotifications = v),
            activeColor: Colors.blueAccent,
          ),
          Divider(color: _border),
          _buildSectionTitle('Notification Types'),
          const SizedBox(height: 8),
          ..._notificationInputs.entries.map((entry) {
            final key = entry.key;
            final data = entry.value as Map;
            final label = data['label']?.toString() ?? key;
            final tip = data['tip']?.toString() ?? '';
            final currentValue = _notificationValues[key] ?? false;
            debugPrint('[NOTIFICATIONS_TOGGLE] Building switch for $key, value: $currentValue');
            return SwitchListTile(
              title: Text(label, style: TextStyle(color: _fg, fontSize: 14)),
              subtitle: tip.isNotEmpty ? Text(tip, style: TextStyle(color: _fgSub, fontSize: 12)) : null,
              value: currentValue,
              onChanged: (v) {
                debugPrint('[NOTIFICATIONS_TOGGLE] $key changed from $currentValue to $v');
                setState(() => _notificationValues[key] = v);
              },
              activeColor: Colors.blueAccent,
            );
          }).toList(),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _loading ? null : _submitNotifications,
              icon: _loading ? SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _fg)) : Icon(Icons.save),
              label: Text(_loading ? 'Saving...' : 'Save Preferences'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blueAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinksTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Social Media Links'),
          const SizedBox(height: 8),
          _buildTextField(controller: _facebookCtrl, label: 'Facebook', hint: 'https://facebook.com/username', icon: Icons.facebook),
          const SizedBox(height: 12),
          _buildTextField(controller: _xCtrl, label: 'X (Twitter)', hint: 'https://x.com/username', icon: Icons.close),
          const SizedBox(height: 12),
          _buildTextField(controller: _linkedinCtrl, label: 'LinkedIn', hint: 'https://linkedin.com/in/username', icon: Icons.business),
          const SizedBox(height: 12),
          _buildTextField(controller: _spotifyCtrl, label: 'Spotify', hint: 'Spotify URL', icon: Icons.music_note),
          const SizedBox(height: 12),
          _buildTextField(controller: _soundcloudCtrl, label: 'SoundCloud', hint: 'SoundCloud URL', icon: Icons.cloud),
          const SizedBox(height: 12),
          _buildTextField(controller: _youtubeCtrl, label: 'YouTube', hint: 'YouTube channel URL', icon: Icons.play_circle_outline),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _loading ? null : _submitLinks,
              icon: _loading ? SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _fg)) : Icon(Icons.save),
              label: Text(_loading ? 'Saving...' : 'Save Links'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blueAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionsTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Active Sessions'),
          const SizedBox(height: 8),
          Text('Manage your active sessions across devices', style: TextStyle(color: _fgSub, fontSize: 13)),
          const SizedBox(height: 16),
          if (_sessions.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('No active sessions', style: TextStyle(color: _fgMid)),
              ),
            )
          else
            ..._sessions.map((sess) => _buildSessionItem(sess)).toList(),
        ],
      ),
    );
  }

  Widget _buildSessionItem(Map sess) {
    final ip = sess['ip'] ?? 'Unknown';
    final platform = sess['platform_type'] ?? 'Unknown';
    final os = sess['os'] ?? 'Unknown';
    final browser = sess['browser'] ?? 'Unknown';
    final lastSeen = sess['time_online'] ?? 'Unknown';
    final isCurrent = sess['is_current'] == true;
    final country = sess['ip_country'] ?? '_U';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCurrent ? Colors.blue.withValues(alpha: 0.1) : _cardBg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrent ? Colors.blueAccent.withValues(alpha: 0.5) : _border,
        ),
      ),
      child: Row(
        children: [
          if (country != '_U')
            Image.network('https://flagsapi.com/$country/flat/32.png', width: 24, height: 24, errorBuilder: (_, __, ___) => Icon(Icons.public, color: _fgMid))
          else
            Icon(Icons.public, color: _fgMid),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(ip, style: TextStyle(color: _fg, fontWeight: FontWeight.w600)),
                    if (isCurrent) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('YOU', style: TextStyle(color: _fg, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text('$platform • $os • $browser', style: TextStyle(color: _fgSub, fontSize: 12)),
                Text('Last seen: $lastSeen', style: TextStyle(color: _fgMid, fontSize: 11)),
              ],
            ),
          ),
          if (!isCurrent)
            IconButton(
              onPressed: () => _revokeSession(sess['session_id'] ?? ''),
              icon: const Icon(Icons.close, color: Colors.redAccent),
            ),
        ],
      ),
    );
  }

  Widget _buildDeleteTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
                    SizedBox(width: 12),
                    Text('Delete Account', style: TextStyle(color: Colors.redAccent, fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Are you sure you want to delete your account? This will remove all of your purchases, uploads, etc. Everything will be removed.',
                  style: TextStyle(color: _fgSub, fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildTextField(controller: _deletePassCtrl, label: 'Password', hint: 'Enter your password', icon: Icons.lock_outline, obscure: true),
          const SizedBox(height: 16),
          CheckboxListTile(
            title: Text('I understand this action is permanent', style: TextStyle(color: _fg)),
            subtitle: Text('All data will be permanently deleted', style: TextStyle(color: _fgSub, fontSize: 12)),
            value: _deleteConfirmed,
            onChanged: (v) => setState(() => _deleteConfirmed = v ?? false),
            activeColor: Colors.redAccent,
            checkColor: _fg,
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_loading || !_deleteConfirmed) ? null : _submitDelete,
              icon: _loading ? SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _fg)) : Icon(Icons.delete_forever),
              label: Text(_loading ? 'Deleting...' : 'Delete Account Permanently'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.redAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverSection() {
    return GestureDetector(
      onTap: _pickCover,
      child: Container(
        height: 150,
        width: double.infinity,
        decoration: BoxDecoration(
          color: _border,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
          image: _getCoverImage(),
        ),
        child: _newCover == null && _currentCover == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.image_outlined, size: 40, color: _fg.withValues(alpha: 0.5)),
                  const SizedBox(height: 8),
                  Text('Tap to add cover photo', style: TextStyle(color: _fg.withValues(alpha: 0.6))),
                ],
              )
            : Align(
                alignment: Alignment.bottomRight,
                child: Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.edit, size: 16, color: Colors.white),
                      const SizedBox(width: 4),
                      const Text('Change', style: TextStyle(color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  DecorationImage? _getCoverImage() {
    if (_newCover != null) {
      return DecorationImage(image: FileImage(_newCover!), fit: BoxFit.cover, opacity: 0.8);
    }
    if (_currentCover != null && _currentCover!.isNotEmpty) {
      return DecorationImage(image: NetworkImage(_currentCover!), fit: BoxFit.cover, opacity: 0.8, onError: (_, __) {});
    }
    return null;
  }

  Widget _buildAvatarSection() {
    return GestureDetector(
      onTap: _pickAvatar,
      child: Stack(
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(60),
              border: Border.all(color: _border, width: 3),
              image: _getAvatarImage(),
            ),
            child: _newAvatar == null && _currentAvatar == null
                ? Icon(Icons.person, size: 50, color: _fgSub)
                : null,
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blueAccent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _bg, width: 2),
              ),
              child: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  DecorationImage? _getAvatarImage() {
    if (_newAvatar != null) {
      return DecorationImage(image: FileImage(_newAvatar!), fit: BoxFit.cover);
    }
    if (_currentAvatar != null && _currentAvatar!.isNotEmpty) {
      return DecorationImage(image: NetworkImage(_currentAvatar!), fit: BoxFit.cover, onError: (_, __) {});
    }
    return null;
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(color: _fg, fontSize: 18, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.redAccent.withValues(alpha: 0.8)),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: _fg.withValues(alpha: 0.8))),
            const SizedBox(height: 20),
            OutlinedButton(onPressed: () => _loadTab(_activeTab), child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool enabled = true,
    bool obscure = false,
    int? maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscure,
      maxLines: maxLines,
      style: TextStyle(color: enabled ? _fg : _fgMid),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: _fgSub),
        hintStyle: TextStyle(color: _fg.withValues(alpha: 0.4)),
        prefixIcon: Icon(icon, color: _fgSub),
        filled: true,
        fillColor: _fg.withValues(alpha: enabled ? 0.08 : 0.04),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _border)),
        disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _cardBg)),
      ),
    );
  }
}
