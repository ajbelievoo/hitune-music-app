import 'package:flutter/material.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/l10n/locale_service.dart';
import '../../core/storage/secure_storage.dart';
import '../downloads/downloads_screen.dart';
import '../player/player_service.dart';
import '../player/sleep_timer_sheet.dart';
import '../player/sound_controls_sheet.dart';
import '../player/widgets/audio_enhance_sheet.dart';
import 'sessions_screen.dart';
import 'user_edit_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = false;
  String? _userName;
  String? _userAvatar;
  String? _coverPhotoUrl;
  String? _email;

  // Social media links
  final Map<String, String?> _socialLinks = {
    'facebook': null,
    'youtube': null,
    'instagram': null,
    'linkedin': null,
    'soundcloud': null,
    'spotify': null,
    'twitter': null,
    'tiktok': null,
  };

  // Notification settings
  Map<String, bool> _notifications = {
    'new_followers': false,
    'new_comments': false,
    'song_releases': false,
    'account_updates': false,
  };

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    _isLoading = true;
    setState(() {});

    try {
      // Load from secure storage
      _userName = await SecureStore.getUserName();
      _userAvatar = await SecureStore.getUserAvatar();

      // Fetch profile data from backend
      final res = await UserEditService().fetchTab(tab: 'profile');
      if (res.isSuccess && res.data != null) {
        final data = res.data!;
        
        // Parse bofForm for all profile data
        final bofForm = data['bofForm'];
        if (bofForm is Map) {
          final inputs = bofForm['inputs'];
          if (inputs is Map) {
            // Cover photo
            final coverInput = inputs['cover_id'];
            if (coverInput is Map) {
              final coverId = coverInput['input']?['value']?.toString();
              if (coverId != null && coverId.isNotEmpty) {
                _coverPhotoUrl = 'https://music.hitune.in/files/$coverId';
              }
            }

            // Avatar
            final avatarInput = inputs['avatar_id'];
            if (avatarInput is Map) {
              final avatarId = avatarInput['input']?['value']?.toString();
              if (avatarId != null && avatarId.isNotEmpty) {
                _userAvatar = 'https://music.hitune.in/files/$avatarId';
                await SecureStore.setUserAvatar(_userAvatar!);
              }
            }

            // Email
            final emailInput = inputs['email'];
            if (emailInput is Map) {
              _email = emailInput['input']?['value']?.toString();
            }

            // Social links - sl_ prefix se aa rahe honge
            final socialPlatforms = ['facebook', 'youtube', 'instagram', 'linkedin', 'soundcloud', 'spotify', 'twitter', 'tiktok'];
            for (final platform in socialPlatforms) {
              final linkInput = inputs['sl_$platform'];
              if (linkInput is Map) {
                final value = linkInput['input']?['value']?.toString();
                if (value != null && value.isNotEmpty) {
                  _socialLinks[platform] = value;
                }
              }
            }
          }
        }

        // User object se bhi check karo
        final user = data['user'];
        if (user is Map) {
          if (_userName == null) {
            _userName = user['name']?.toString() ?? user['display_name']?.toString();
            if (_userName != null) await SecureStore.setUserName(_userName!);
          }
          if (_email == null) _email = user['email']?.toString();
          if (_userAvatar == null) {
            final avatarId = user['avatar_id']?.toString();
            if (avatarId != null && avatarId.isNotEmpty) {
              _userAvatar = 'https://music.hitune.in/files/$avatarId';
              await SecureStore.setUserAvatar(_userAvatar!);
            }
          }
        }
      }

      // Fetch notifications tab
      final notifRes = await UserEditService().fetchTab(tab: 'notifications');
      if (notifRes.isSuccess && notifRes.data != null) {
        final data = notifRes.data!;
        final bofForm = data['bofForm'];
        if (bofForm is Map) {
          final inputs = bofForm['inputs'];
          if (inputs is Map) {
            // Parse notification toggles
            _notifications['new_followers'] = inputs['nf_new_followers']?['input']?['value'] == 1 || inputs['nf_new_followers']?['input']?['value'] == '1' || inputs['nf_new_followers']?['input']?['value'] == true;
            _notifications['new_comments'] = inputs['nf_new_comments']?['input']?['value'] == 1 || inputs['nf_new_comments']?['input']?['value'] == '1' || inputs['nf_new_comments']?['input']?['value'] == true;
            _notifications['song_releases'] = inputs['nf_new_song_release']?['input']?['value'] == 1 || inputs['nf_new_song_release']?['input']?['value'] == '1' || inputs['nf_new_song_release']?['input']?['value'] == true;
            _notifications['account_updates'] = inputs['nf_account_update']?['input']?['value'] == 1 || inputs['nf_account_update']?['input']?['value'] == '1' || inputs['nf_account_update']?['input']?['value'] == true;
          }
        }
      }
    } catch (e) {
      debugPrint('[SETTINGS] Error loading data: $e');
    }

    _isLoading = false;
    setState(() {});
  }

  Future<void> _showDeleteAccountDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Delete Account', style: TextStyle(color: Colors.red)),
        content: const Text(
          'Are you sure you want to delete your account? This action cannot be undone.',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // TODO: Call API to delete account
      await SecureStore.clearUserSession();
      await SecureStore.clearUserToken();
      await SecureStore.clearUserRole();
      await SecureStore.clearUserId();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const Scaffold(body: Center(child: Text('Logged out')))), 
          (route) => false,
        );
      }
    }
  }

  void _showLanguagePicker() {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('App Language', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
            for (final code in AppStrings.supportedLocales)
              RadioListTile<String>(
                value: code,
                groupValue: LocaleService.instance.languageCode,
                title: Text(code == 'hi' ? 'हिन्दी' : 'English'),
                onChanged: (v) async {
                  if (v != null) await LocaleService.instance.setLanguage(v);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  if (mounted) setState(() {});
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // Profile Header with Cover Photo
                _buildProfileHeader(),
                
                const SizedBox(height: 20),
                
                // Account Section
                _buildSectionHeader('Account'),
                _buildSettingTile(
                  icon: Icons.security,
                  title: 'Security',
                  subtitle: 'Password, 2FA',
                  onTap: () => _showSecurityOptions(),
                ),
                _buildSettingTile(
                  icon: Icons.notifications_outlined,
                  title: 'Notifications',
                  subtitle: 'Manage your notification preferences',
                  onTap: () => _openNotificationsScreen(),
                ),
                _buildSettingTile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy',
                  onTap: () {},
                ),

                const SizedBox(height: 20),

                // Playback Section
                _buildSectionHeader('Playback'),
                _buildSettingTile(
                  icon: Icons.bedtime_outlined,
                  title: 'Sleep Timer',
                  subtitle: 'Stop music after a set time',
                  onTap: () => SleepTimerSheet.show(context, PlayerService.instance),
                ),
                _buildSettingTile(
                  icon: Icons.speed_rounded,
                  title: 'Speed & Pitch',
                  subtitle: 'Playback speed, pitch, skip silence',
                  onTap: () => SoundControlsSheet.show(context, PlayerService.instance),
                ),
                _buildSettingTile(
                  icon: Icons.graphic_eq_rounded,
                  title: 'Equalizer',
                  subtitle: 'EQ bands, bass, surround',
                  onTap: () => showAudioEnhanceSheet(context, PlayerService.instance),
                ),
                _buildSettingTile(
                  icon: Icons.download_rounded,
                  title: 'Downloads',
                  subtitle: 'Offline songs on this device',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const DownloadsScreen()),
                  ),
                ),
                _buildSettingTile(
                  icon: Icons.language_rounded,
                  title: 'Language',
                  subtitle: LocaleService.instance.languageCode == 'hi' ? 'हिन्दी' : 'English',
                  onTap: _showLanguagePicker,
                ),

                const SizedBox(height: 20),

                // Social Media Links Section
                _buildSectionHeader('Social Media'),
                _buildSocialMediaTiles(),
                
                const SizedBox(height: 20),
                
                // Support Section
                _buildSectionHeader('Support'),
                _buildSettingTile(
                  icon: Icons.help_outline,
                  title: 'Help Center',
                  onTap: () {},
                ),
                _buildSettingTile(
                  icon: Icons.feedback_outlined,
                  title: 'Send Feedback',
                  onTap: () {},
                ),
                
                const SizedBox(height: 20),
                
                // Danger Zone
                _buildSectionHeader('Danger Zone', color: Colors.red),
                _buildSettingTile(
                  icon: Icons.delete_forever,
                  title: 'Delete Account',
                  titleColor: Colors.red,
                  onTap: _showDeleteAccountDialog,
                ),
                
                const SizedBox(height: 40),
                
                // Logout Button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await SecureStore.clearUserSession();
                      await SecureStore.clearUserToken();
                      await SecureStore.clearUserRole();
                      await SecureStore.clearUserId();
                      if (mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const SizedBox.shrink()),
                          (route) => false,
                        );
                      }
                    },
                    icon: const Icon(Icons.logout, color: Colors.red),
                    label: const Text('Logout', style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                
                const SizedBox(height: 40),
              ],
            ),
    );
  }

  Widget _buildProfileHeader() {
    return Stack(
      children: [
        // Cover Photo
        Container(
          height: 180,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.grey[800],
            image: _coverPhotoUrl != null
                ? DecorationImage(
                    image: NetworkImage(_coverPhotoUrl!),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: _coverPhotoUrl == null
              ? Center(
                  child: Icon(
                    Icons.image,
                    size: 50,
                    color: Colors.grey[600],
                  ),
                )
              : null,
        ),
        
        // Edit Cover Photo Button
        Positioned(
          bottom: 8,
          right: 8,
          child: GestureDetector(
            onTap: () => _showCoverPhotoOptions(),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.camera_alt,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
        
        // Avatar and Name overlay
        Positioned(
          bottom: 0,
          left: 16,
          child: Transform.translate(
            offset: const Offset(0, 40),
            child: Row(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 4),
                    image: _userAvatar != null
                        ? DecorationImage(
                            image: NetworkImage(_userAvatar!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: _userAvatar == null
                      ? Icon(Icons.person, size: 40, color: Colors.grey[600])
                      : null,
                ),
                const SizedBox(width: 12),
                Text(
                  _userName ?? 'User',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: color ?? Colors.grey[400],
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    Color? titleColor,
  }) {
    return ListTile(
      leading: Icon(icon, color: titleColor ?? Colors.grey[400]),
      title: Text(
        title,
        style: TextStyle(color: titleColor ?? Colors.white),
      ),
      subtitle: subtitle != null
          ? Text(subtitle, style: TextStyle(color: Colors.grey[500]))
          : null,
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }

  Widget _buildSocialMediaTiles() {
    final socialIcons = {
      'facebook': Icons.facebook,
      'youtube': Icons.play_circle_outline,
      'instagram': Icons.camera_alt,
      'linkedin': Icons.link,
      'soundcloud': Icons.music_note,
      'spotify': Icons.music_video,
      'twitter': Icons.chat_bubble_outline,
      'tiktok': Icons.music_note_outlined,
    };

    return Column(
      children: _socialLinks.entries.map((entry) {
        final platform = entry.key;
        final url = entry.value;
        final icon = socialIcons[platform] ?? Icons.link;
        
        return ListTile(
          leading: Icon(icon, color: Colors.grey[400]),
          title: Text(
            platform[0].toUpperCase() + platform.substring(1),
            style: const TextStyle(color: Colors.white),
          ),
          subtitle: Text(
            url ?? 'Not connected',
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
          onTap: () => _showSocialLinkDialog(platform, url),
        );
      }).toList(),
    );
  }

  void _openNotificationsScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            title: const Text('Notifications'),
          ),
          body: ListView(
            children: [
              _buildNotificationTile('New Followers', 'nf_new_followers', _notifications['new_followers'] ?? false),
              _buildNotificationTile('New Comments', 'nf_new_comments', _notifications['new_comments'] ?? false),
              _buildNotificationTile('Song Releases', 'nf_new_song_release', _notifications['song_releases'] ?? false),
              _buildNotificationTile('Account Updates', 'nf_account_update', _notifications['account_updates'] ?? false),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationTile(String title, String key, bool value) {
    return ListTile(
      title: Text(title, style: const TextStyle(color: Colors.white)),
      trailing: Switch(
        value: value,
        onChanged: (newValue) => _updateNotification(key, newValue),
        activeColor: Colors.blueAccent,
      ),
    );
  }

  Future<void> _updateNotification(String key, bool value) async {
    setState(() => _notifications[key] = value);
    
    try {
      // Update backend using correct method
      final res = await UserEditService().submitNotifications(
        notifications: {key: value},
      );
      
      if (!res.isSuccess) {
        // Revert on failure
        setState(() => _notifications[key] = !value);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update: ${res.error?.message ?? "Unknown error"}')),
          );
        }
      }
    } catch (e) {
      setState(() => _notifications[key] = !value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showSecurityOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.lock_outline, color: Colors.white),
            title: const Text('Change Password', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              _openChangePasswordScreen();
            },
          ),
          ListTile(
            leading: const Icon(Icons.verified_user_outlined, color: Colors.white),
            title: const Text('Two-Factor Authentication', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('2FA is currently unavailable')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.devices_outlined, color: Colors.white),
            title: const Text('Active Sessions', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              SessionsScreen.openWithAuth(context);
            },
          ),
        ],
      ),
    );
  }

  void _openChangePasswordScreen() {
    final currentPassCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            return Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(
                backgroundColor: Colors.black,
                title: const Text('Change Password'),
              ),
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: currentPassCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Current Password',
                        labelStyle: TextStyle(color: Colors.grey),
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: newPassCtrl,
                      decoration: const InputDecoration(
                        labelText: 'New Password',
                        labelStyle: TextStyle(color: Colors.grey),
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: confirmPassCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Confirm New Password',
                        labelStyle: TextStyle(color: Colors.grey),
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () async {
                        final oldPass = currentPassCtrl.text.trim();
                        final newPass = newPassCtrl.text.trim();
                        final confirmPass = confirmPassCtrl.text.trim();
                        
                        if (oldPass.isEmpty || newPass.isEmpty || confirmPass.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please fill all fields')),
                          );
                          return;
                        }
                        
                        if (newPass != confirmPass) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Passwords do not match')),
                          );
                          return;
                        }
                        
                        setDialogState(() {});
                        
                        try {
                          final res = await UserEditService().submitSecurity(
                            oldPassword: oldPass,
                            newPassword: newPass,
                          );
                          
                          if (res.isSuccess) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Password updated successfully!')),
                              );
                              Navigator.pop(context);
                            }
                          } else {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed: ${res.error?.message}')),
                              );
                            }
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e')),
                            );
                          }
                        }
                      },
                      child: const Text('Update Password'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showCoverPhotoOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library, color: Colors.white),
            title: const Text('Choose from Gallery', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              // TODO: Implement image picker
            },
          ),
          ListTile(
            leading: const Icon(Icons.link, color: Colors.white),
            title: const Text('Enter Image URL', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              _showCoverUrlDialog();
            },
          ),
          if (_coverPhotoUrl != null)
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Remove Cover Photo', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                setState(() => _coverPhotoUrl = null);
              },
            ),
        ],
      ),
    );
  }

  void _showCoverUrlDialog() {
    final controller = TextEditingController(text: _coverPhotoUrl);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Cover Photo URL', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'https://example.com/image.jpg',
            hintStyle: TextStyle(color: Colors.grey),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              setState(() => _coverPhotoUrl = controller.text);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showSocialLinkDialog(String platform, String? currentUrl) {
    final controller = TextEditingController(text: currentUrl);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(
          '${platform[0].toUpperCase() + platform.substring(1)} Link',
          style: const TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'https://$platform.com/username',
            hintStyle: const TextStyle(color: Colors.grey),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final url = controller.text.trim();
              Navigator.pop(context);
              
              debugPrint('[SETTINGS] Saving social link: platform=$platform, url=$url');
              
              // Update local state
              setState(() => _socialLinks[platform] = url.isEmpty ? null : url);
              
              // Save to backend
              try {
                final linksData = url.isEmpty ? <String, String>{} : {'sl_$platform': url};
                debugPrint('[SETTINGS] Calling submitLinks with: $linksData');
                
                final res = await UserEditService().submitLinks(links: linksData);
                
                debugPrint('[SETTINGS] submitLinks result: isSuccess=${res.isSuccess}, error=${res.error?.message}');
                
                if (res.isSuccess) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Social link saved!')),
                    );
                  }
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to save: ${res.error?.message}')),
                  );
                }
              } catch (e, st) {
                debugPrint('[SETTINGS] Error saving social link: $e');
                debugPrint('[SETTINGS] Stack trace: $st');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
