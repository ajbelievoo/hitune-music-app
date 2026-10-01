import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/models/user_context.dart';
import '../auth/login_screen.dart';
import '../auth/signup_screen.dart';
import '../auth/auth_state_service.dart';
import '../analytics/analytics_screen.dart';
import '../analytics/analytics_service.dart';
import '../config/client_config_service.dart';
import '../../core/storage/secure_storage.dart';
import '../../core/theme/theme_service.dart';
import '../auth/auth_gate.dart';
import 'edit_profile_screen.dart';
import 'sessions_screen.dart';
import 'upgrade_plans_screen.dart';
import 'user_edit_service.dart';
import '../library/liked_songs_screen.dart';
import '../library/library_screen.dart';
import '../library/recently_played_screen.dart';
import '../library/playlists_screen.dart';
import '../other_projects/other_projects_screen.dart';
import '../subscription/subscription_service.dart';
import '../developer/developer_screen.dart';
import '../developer/developer_service.dart';
import '../iyol/iyol_deeplink.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<UserContext> _ctx;
  bool _hasSession = false;
  String? _userName;
  String? _userAvatar;
  String? _userCover;

  @override
  void initState() {
    super.initState();
    _ctx = _load();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<UserContext> _load() async {
    final sessId = await SecureStore.getUserSessId();
    final sessKey = await SecureStore.getUserSessKey();
    _hasSession = (sessId != null && sessId.isNotEmpty) && (sessKey != null && sessKey.isNotEmpty);
    
    debugPrint('[PROFILE] _load() - sessId: ${sessId != null ? 'SET' : 'NULL'}, sessKey: ${sessKey != null ? 'SET' : 'NULL'}, _hasSession: $_hasSession');
    
    // Load cached user profile
    _userName = await SecureStore.getUserName();
    _userAvatar = await SecureStore.getUserAvatar();
    _userCover = await SecureStore.getUserCover();
    
    debugPrint('[PROFILE] _load() - cached name: $_userName, avatar: ${_userAvatar != null ? 'SET' : 'NULL'}, cover: ${_userCover != null ? 'SET' : 'NULL'}');
    
    // Sync with backend
    final res = await ClientConfigService().fetchClientConfig();
    if (!res.isSuccess) {
      debugPrint('[PROFILE] _load() - client_config failed: ${res.error?.message}');
      return UserContext.load();
    }
    
    debugPrint('[PROFILE] _load() - client_config success');
    
    // Fetch fresh profile data if logged in
    if (_hasSession) {
      debugPrint('[PROFILE] _load() - fetching user profile...');
      await _fetchUserProfile();
      // Trigger UI rebuild with updated profile data
      if (mounted) setState(() {});
    } else {
      debugPrint('[PROFILE] _load() - no session, skipping profile fetch');
    }
    
    return UserContext.load();
  }
  
  Future<void> _fetchUserProfile() async {
    try {
      debugPrint('[PROFILE] _fetchUserProfile() - calling UserEditService...');
      final res = await UserEditService().fetchTab(tab: 'profile');
      debugPrint('[PROFILE] _fetchUserProfile() - result: isSuccess=${res.isSuccess}, error=${res.error?.code}');
      if (res.isSuccess && res.data != null) {
        var changed = false;
        final data = res.data!;
        debugPrint('[PROFILE] _fetchUserProfile() - data keys: ${data.keys}');
        
        // Print ALL data for debugging
        debugPrint('[PROFILE] FULL DATA: ${jsonEncode(data)}');
        
        final bofForm = data['bofForm'];
        debugPrint('[PROFILE] _fetchUserProfile() - bofForm type: ${bofForm.runtimeType}');
        
        if (bofForm is Map) {
          final inputs = bofForm['inputs'];
          debugPrint('[PROFILE] _fetchUserProfile() - inputs type: ${inputs.runtimeType}');
          if (inputs is Map) {
            // Print ALL input keys
            debugPrint('[PROFILE] ALL INPUT KEYS: ${inputs.keys.toList()}');
            
            // Fetch name
            final nameInput = inputs['name'];
            debugPrint('[PROFILE] _fetchUserProfile() - nameInput type: ${nameInput.runtimeType}');
            if (nameInput is Map) {
              final inputObj = nameInput['input'];
              debugPrint('[PROFILE] _fetchUserProfile() - inputObj type: ${inputObj.runtimeType}');
              if (inputObj is Map) {
                final name = inputObj['value']?.toString();
                debugPrint('[PROFILE] _fetchUserProfile() - extracted name: $name');
                if (name != null && name.isNotEmpty) {
                  if (_userName != name) {
                    _userName = name;
                    await SecureStore.setUserName(name);
                    changed = true;
                  }
                  debugPrint('[PROFILE] _fetchUserProfile() - _userName set to: $_userName');
                }
              }
            }
            
            // Fetch avatar from avatar_id
            final avatarInput = inputs['avatar_id'];
            debugPrint('[PROFILE] _fetchUserProfile() - avatarInput: $avatarInput');
            if (avatarInput is Map) {
              final avatarInputObj = avatarInput['input'];
              if (avatarInputObj is Map) {
                final preview = avatarInputObj['preview']?.toString();
                final avatarId = avatarInputObj['value']?.toString();
                debugPrint('[PROFILE] _fetchUserProfile() - avatarId from inputs: $avatarId');
                String? avatarUrl;
                if (preview != null && preview.trim().isNotEmpty) {
                  avatarUrl = preview.trim();
                } else if (avatarId != null && avatarId.trim().isNotEmpty) {
                  avatarUrl = 'https://music.hitune.in/files/${avatarId.trim()}';
                }
                if (avatarUrl != null && avatarUrl.isNotEmpty) {
                  if (_userAvatar != avatarUrl) {
                    _userAvatar = avatarUrl;
                    await SecureStore.setUserAvatar(avatarUrl);
                    changed = true;
                  }
                  debugPrint('[PROFILE] _fetchUserProfile() - _userAvatar set from inputs to: $_userAvatar');
                }
              }
              // Also check bof_file_pass which might contain the file info
              final bofFilePass = avatarInput['bof_file_pass'];
              debugPrint('[PROFILE] _fetchUserProfile() - bof_file_pass: $bofFilePass');
            }
            
            // Look for avatar in other possible fields
            for (final key in ['avatar', 'photo', 'picture', 'image', 'profile_pic', 'profile_photo']) {
              if (inputs.containsKey(key)) {
                debugPrint('[PROFILE] Found possible avatar field: $key = ${inputs[key]}');
              }
            }
          }
        }
        
        // Check messages array for user data
        final messages = data['messages'];
        if (messages is List && messages.isNotEmpty) {
          debugPrint('[PROFILE] _fetchUserProfile() - checking messages...');
          for (var i = 0; i < messages.length; i++) {
            final msg = messages[i];
            if (msg is Map) {
              debugPrint('[PROFILE] Message $i keys: ${msg.keys}');
              // Check for avatar in message - handle both String URL and Map with path
              String? msgAvatar;
              if (msg['avatar_url'] != null) {
                msgAvatar = msg['avatar_url']?.toString();
              } else if (msg['avatar'] is Map) {
                final avatarPath = msg['avatar']['path']?.toString();
                if (avatarPath != null && avatarPath.isNotEmpty) {
                  msgAvatar = 'https://music.hitune.in/$avatarPath';
                }
              } else if (msg['avatar'] != null) {
                msgAvatar = msg['avatar']?.toString();
              } else if (msg['photo'] != null) {
                msgAvatar = msg['photo']?.toString();
              }
              
              if (msgAvatar != null && msgAvatar.isNotEmpty) {
                debugPrint('[PROFILE] Found avatar in message $i: $msgAvatar');
                _userAvatar ??= msgAvatar;
              }
            }
          }
        }
        
        // Check for user object (new from backend fix)
        final user = data['user'];
        debugPrint('[PROFILE] _fetchUserProfile() - user object: $user');
        if (user is Map) {
          debugPrint('[PROFILE] _fetchUserProfile() - user keys: ${user.keys.toList()}');
          
          // Get avatar from user object
          {
            String? avatarUrl;
            if (user['avatar_url'] != null) {
              avatarUrl = user['avatar_url']?.toString();
            }
            if ((avatarUrl == null || avatarUrl.isEmpty) && user['avatar'] is Map) {
              final avatarMap = user['avatar'] as Map;
              final path = avatarMap['path']?.toString();
              if (path != null && path.isNotEmpty) {
                avatarUrl = 'https://music.hitune.in/$path';
              }
            }
            if ((avatarUrl == null || avatarUrl.isEmpty) && user['photo'] != null) {
              avatarUrl = user['photo']?.toString();
            }
            debugPrint('[PROFILE] _fetchUserProfile() - avatar from user object: $avatarUrl');
            if (avatarUrl != null && avatarUrl.isNotEmpty && _userAvatar != avatarUrl) {
              _userAvatar = avatarUrl;
              await SecureStore.setUserAvatar(avatarUrl);
              changed = true;
              debugPrint('[PROFILE] _fetchUserProfile() - _userAvatar set from user object to: $_userAvatar');
            }
          }
          
          // Get cover from user object
          {
            String? coverUrl;
            if (user['cover_url'] != null) {
              coverUrl = user['cover_url']?.toString();
            }
            if ((coverUrl == null || coverUrl.isEmpty) && user['cover'] is Map) {
              final coverMap = user['cover'] as Map;
              final path = coverMap['path']?.toString();
              if (path != null && path.isNotEmpty) {
                coverUrl = 'https://music.hitune.in/$path';
              }
            }
            if ((coverUrl == null || coverUrl.isEmpty) && user['cover_photo'] != null) {
              coverUrl = user['cover_photo']?.toString();
            }
            debugPrint('[PROFILE] _fetchUserProfile() - cover from user object: $coverUrl');
            if (coverUrl != null && coverUrl.isNotEmpty && _userCover != coverUrl) {
              _userCover = coverUrl;
              await SecureStore.setUserCover(coverUrl);
              changed = true;
              debugPrint('[PROFILE] _fetchUserProfile() - _userCover set from user object to: $_userCover');
            }
          }
          
          // Get name from user object if not already set
          if (_userName == null) {
            final name = user['name']?.toString() ?? user['display_name']?.toString();
            if (name != null && name.isNotEmpty) {
              _userName = name;
              await SecureStore.setUserName(name);
              changed = true;
              debugPrint('[PROFILE] _fetchUserProfile() - _userName set from user object to: $_userName');
            }
          }
        }

        if (changed && mounted) {
          setState(() {});
          debugPrint('[PROFILE] _fetchUserProfile() - setState called after user data update');
        }
      }
      debugPrint('[PROFILE] _fetchUserProfile() - END: _userName=$_userName, _userAvatar=$_userAvatar');
    } catch (e, stack) {
      debugPrint('[PROFILE] _fetchUserProfile() - ERROR: $e');
      debugPrint('[PROFILE] _fetchUserProfile() - STACK: $stack');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: FutureBuilder<UserContext>(
        future: _ctx,
        builder: (context, snapshot) {
          final isLoggedIn = _hasSession;

          // Session state isn't known until _load() resolves the SecureStore
          // reads — showing the guest view before that flashes "Sign In" to
          // logged-in users for a moment.
          if (snapshot.connectionState != ConnectionState.done &&
              !isLoggedIn) {
            return const Center(child: CircularProgressIndicator());
          }

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _ctx = _load();
              });
            },
            child: CustomScrollView(
            slivers: [
              // Brand-gradient header with centered avatar
              SliverToBoxAdapter(child: _buildHeader(theme, isDark, isLoggedIn, snapshot.data)),

              // Profile Content
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),

                      // Action Buttons
                      if (isLoggedIn)
                        Row(
                          children: [
                            Expanded(
                              child: Material(
                                borderRadius: BorderRadius.circular(26),
                                clipBehavior: Clip.antiAlias,
                                child: Ink(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [_brandCyan, _brandPink],
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    ),
                                  ),
                                  child: InkWell(
                                    onTap: () => _openEditProfile(context),
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 13),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.edit, size: 17, color: Colors.white),
                                          SizedBox(width: 8),
                                          Text(
                                            'Edit Profile',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  showModalBottomSheet(
                                    context: context,
                                    isScrollControlled: true,
                                    backgroundColor: Colors.transparent,
                                    builder: (context) {
                                      final theme = Theme.of(context);
                                      final isDark = theme.brightness == Brightness.dark;
                                      return Container(
                                        height: MediaQuery.of(context).size.height * 0.6,
                                        decoration: BoxDecoration(
                                          color: theme.scaffoldBackgroundColor,
                                          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                                        ),
                                        child: Column(
                                          children: [
                                            // Drag handle
                                            Container(
                                              margin: const EdgeInsets.only(top: 12, bottom: 8),
                                              width: 40,
                                              height: 4,
                                              decoration: BoxDecoration(
                                                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.3),
                                                borderRadius: BorderRadius.circular(2),
                                              ),
                                            ),
                                            // Close button row
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text(
                                                    'Your Library',
                                                    style: TextStyle(
                                                      color: isDark ? Colors.white : Colors.black,
                                                      fontSize: 22,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                  IconButton(
                                                    onPressed: () => Navigator.of(context).pop(),
                                                    icon: Icon(
                                                      Icons.close,
                                                      color: isDark ? Colors.white : Colors.black,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const Divider(height: 1),
                                            // Library content
                                            const Expanded(child: LibraryScreen(useScaffold: false)),
                                          ],
                                        ),
                                      );
                                    },
                                  );
                                },
                                icon: const Icon(Icons.library_music, size: 18),
                                label: const Text('Library'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: isDark ? Colors.white : Colors.black,
                                  side: BorderSide(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.3)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        Column(
                          children: [
                            FilledButton.icon(
                              onPressed: () => _openLogin(context),
                              icon: const Icon(Icons.login),
                              label: const Text('Sign In'),
                              style: FilledButton.styleFrom(
                                backgroundColor: _brandCyan,
                                minimumSize: const Size(double.infinity, 48),
                              ),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () => _openSignup(context),
                              icon: const Icon(Icons.person_add),
                              label: const Text('Create Account'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: isDark ? Colors.white : Colors.black,
                                side: BorderSide(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.3)),
                                minimumSize: const Size(double.infinity, 48),
                              ),
                            ),
                          ],
                        ),
                      
                      const SizedBox(height: 30),
                      
                      // Menu Grid
                      if (isLoggedIn) ...[
                        _buildSectionTitle('Your Account'),
                        const SizedBox(height: 12),
                        _buildMenuGrid([
                          _MenuItem(Icons.favorite_outline, 'Liked Songs', _brandPink, () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const LikedSongsScreen()),
                            );
                          }),
                          _MenuItem(Icons.history, 'Recently Played', _brandCyan, () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const RecentlyPlayedScreen()),
                            );
                          }),
                          _MenuItem(Icons.playlist_play, 'Playlists', _brandViolet, () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const PlaylistsScreen()),
                            );
                          }),
                          _MenuItem(Icons.account_balance_wallet, 'Wallet', _brandTeal, () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const EditProfileScreen(initialTabIndex: 2)),
                            );
                          }),
                        ]),
                        const SizedBox(height: 24),
                        
                        _buildSectionTitle('Account Settings'),
                        const SizedBox(height: 12),
                        _buildMenuList([
                          _MenuItem(Icons.verified_outlined, 'Artist Panel', _brandViolet, () => launchUrl(
                            Uri.parse('https://distribution.hitune.in/index.php?q=artist-panel#verification'),
                            mode: LaunchMode.externalApplication)),
                          _MenuItem(Icons.workspace_premium, 'Upgrade Plans', _brandGold, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UpgradePlansScreen()))),
                          _MenuItem(Icons.devices_outlined, 'Sessions', _brandCyan, () => SessionsScreen.openWithAuth(context)),
                          _MenuItem(Icons.video_library_outlined, 'IyolMe Reels', _brandPink, () => IyolDeepLink.openApp()),
                          _MenuItem(Icons.apps_outage, 'Other Apps', _brandPink, () {
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OtherProjectsScreen()));
                          }),
                          if (DeveloperService.instance.isPortalEnabled)
                            _MenuItem(Icons.code, 'Developer API', _brandTeal, () => DeveloperScreen.openWithAuth(context)),
                        ]),
                        const SizedBox(height: 24),
                        
                        // Logout
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await SecureStore.clearUserSession();
                              await SecureStore.clearUserToken();
                              await SecureStore.clearUserRole();
                              await SecureStore.clearUserId();
                              AuthStateService().notifyLoggedOut();
                              if (context.mounted) {
                                setState(() {
                                  _ctx = _load();
                                });
                              }
                            },
                            icon: const Icon(Icons.logout, color: Colors.redAccent),
                            label: const Text('Logout', style: TextStyle(color: Colors.redAccent)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          ),
          );
        },
      ),
    );
  }

  // Brand palette (matches the app logo glow).
  static const Color _brandCyan = Color(0xFF0FA8D4);
  static const Color _brandPink = Color(0xFFE56BD8);
  static const Color _brandViolet = Color(0xFF8B7CF6);
  static const Color _brandTeal = Color(0xFF2DD4BF);
  static const Color _brandGold = Color(0xFFFFB340);

  Widget _buildHeader(ThemeData theme, bool isDark, bool isLoggedIn, UserContext? ctx) {
    final fg = isDark ? Colors.white : Colors.black;
    final muted = fg.withValues(alpha: 0.6);
    final plan = SubscriptionService.instance.currentPlan;
    final isPaid = SubscriptionService.instance.isPaid;

    return Column(
      children: [
        SizedBox(
          height: 296, // 240 cover + 56 avatar overlap
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Cover photo / brand glow — occupies the top 240px.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 240,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (isLoggedIn && _userCover != null)
                      // Blur + slight zoom — makes even a low-res cover look
                      // like an intentional frosted-glass banner.
                      ClipRect(
                        child: ImageFiltered(
                          imageFilter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                          child: Transform.scale(
                            scale: 1.25,
                            child: Image.network(
                              _userCover!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              _brandCyan.withValues(alpha: isDark ? 0.40 : 0.30),
                              _brandViolet.withValues(alpha: isDark ? 0.30 : 0.22),
                              _brandPink.withValues(alpha: isDark ? 0.35 : 0.26),
                            ],
                          ),
                        ),
                      ),
                    // Scrim fading into the scaffold background.
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.25),
                            theme.scaffoldBackgroundColor.withValues(alpha: 0.35),
                            theme.scaffoldBackgroundColor,
                          ],
                          stops: const [0.0, 0.55, 1.0],
                        ),
                      ),
                    ),
                    // Top bar: back + refresh.
                    SafeArea(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            children: [
                              IconButton(
                                onPressed: () => Navigator.of(context).maybePop(),
                                icon: const Icon(Icons.arrow_back, color: Colors.white),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black.withValues(alpha: 0.25),
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    _ctx = _load();
                                  });
                                },
                                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black.withValues(alpha: 0.25),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Avatar overlapping the cover's bottom edge.
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 112,
                        height: 112,
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [_brandCyan, _brandPink],
                          ),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                          ),
                          child: ClipOval(
                            child: isLoggedIn && _userAvatar != null
                                ? Image.network(_userAvatar!, fit: BoxFit.cover)
                                : Icon(
                                    Icons.person_outline,
                                    size: 52,
                                    color: muted,
                                  ),
                          ),
                        ),
                      ),
                      if (isLoggedIn)
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: GestureDetector(
                            onTap: () => _openEditProfile(context),
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: _brandCyan,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: theme.scaffoldBackgroundColor,
                                  width: 3,
                                ),
                              ),
                              child: const Icon(Icons.edit, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Name, centered.
        Text(
          isLoggedIn ? (_userName ?? 'User') : 'Guest User',
          style: TextStyle(
            color: fg,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        if (isLoggedIn) ...[
          const SizedBox(height: 8),
          // Role + plan chips — role only when the backend actually marks
          // this user as staff; plan always reflects the subscription.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (ctx?.isAdmin == true) _ProfileBadge(label: 'ADMIN', color: _brandCyan),
              if (ctx?.isModerator == true && ctx?.isAdmin != true)
                _ProfileBadge(label: 'MODERATOR', color: _brandViolet),
              _ProfileBadge(
                label: plan.toUpperCase(),
                color: isPaid ? _brandGold : muted,
                icon: isPaid ? Icons.workspace_premium : null,
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Text(
          isLoggedIn ? 'Member' : 'Sign in to access your profile',
          style: TextStyle(color: muted, fontSize: 13),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        final isDark = themeService.isDarkMode;
        return Text(
          title,
          style: TextStyle(
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.6),
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        );
      },
    );
  }

  Widget _buildMenuGrid(List<_MenuItem> items) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        final isDark = themeService.isDarkMode;
        
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: items.map((item) => _buildGridTile(item, isDark)).toList(),
        );
      },
    );
  }

  Widget _buildGridTile(_MenuItem item, bool isDark) {
    return GestureDetector(
      onTap: item.onTap,
      child: Container(
        decoration: BoxDecoration(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(item.icon, color: item.color, size: 22),
            ),
            const SizedBox(height: 10),
            Text(
              item.title,
              style: TextStyle(
                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.9),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuList(List<_MenuItem> items) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        // Add theme toggle to items list
        final allItems = [
          ...items,
          _MenuItem(
            themeService.isDarkMode ? Icons.light_mode : Icons.dark_mode,
            themeService.isDarkMode ? 'Light Mode' : 'Dark Mode',
            _brandCyan,
            () => themeService.toggleTheme(),
          ),
        ];
        
        final isDark = themeService.isDarkMode;
        
        return Container(
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08)),
          ),
          child: Column(
            children: allItems.asMap().entries.map((entry) {
              final i = entry.key;
              final item = entry.value;
              return Column(
                children: [
                  ListTile(
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: item.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(item.icon, color: item.color, size: 20),
                    ),
                    title: Text(
                      item.title,
                      style: TextStyle(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.9), fontWeight: FontWeight.w600),
                    ),
                    trailing: Icon(Icons.chevron_right, color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.4)),
                    onTap: item.onTap,
                  ),
                  if (i < allItems.length - 1)
                    Divider(height: 1, indent: 68, color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06)),
                ],
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Future<void> _openLogin(BuildContext context) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const LoginScreen()),
    );
    if (ok == true && context.mounted) {
      setState(() {
        _ctx = _load();
      });
    }
  }

  Future<void> _openSignup(BuildContext context) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const SignupScreen()),
    );
    if (ok == true && context.mounted) {
      setState(() {
        _ctx = _load();
      });
    }
  }

  Future<void> _openEditProfile(BuildContext context) async {
    final ok = await AuthGate.ensureLoggedIn(context, reason: 'Login required to edit profile.');
    if (!ok) return;
    if (!context.mounted) return;
    
    debugPrint('[PROFILE] Opening EditProfileScreen...');
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const EditProfileScreen()),
    );
    
    debugPrint('[PROFILE] EditProfileScreen returned: result=$result');
    
    if (context.mounted) {
      // Always refresh profile data when returning from edit
      debugPrint('[PROFILE] Refreshing profile data after edit...');
      setState(() {
        _ctx = _load();
      });
    }
  }

  // Debug and analytics methods - currently unused but kept for future
  // ignore: unused_element
  Future<void> _showDebugSheet(BuildContext context) async {
    final loggedInNow = await AuthGate.isLoggedIn();
    final sessId = await SecureStore.getUserSessId();
    final sessKey = await SecureStore.getUserSessKey();
    
    // Fetch fresh API data for debugging
    String apiResponse = 'Loading...';
    try {
      final res = await UserEditService().fetchTab(tab: 'profile');
      if (res.isSuccess && res.data != null) {
        final user = res.data!['user'];
        final bofForm = res.data!['bofForm'];
        apiResponse = 'User object: $user\n\nAvatar from user: ${user is Map ? (user['avatar_url'] ?? (user['avatar'] is Map ? user['avatar']['path'] : user['avatar']) ?? user['photo']) : 'N/A'}\n\nbofForm avatar_id: ${bofForm is Map ? (bofForm['inputs'] is Map ? (bofForm['inputs']['avatar_id'] is Map ? (bofForm['inputs']['avatar_id']['input'] is Map ? bofForm['inputs']['avatar_id']['input']['value'] : null) : null) : null) : 'N/A'}';
        if (bofForm is Map && bofForm['inputs'] is Map && bofForm['inputs']['avatar_id'] is Map && bofForm['inputs']['avatar_id']['input'] is Map) {
          apiResponse += '\n\nbofForm avatar_id: ${bofForm['inputs']['avatar_id']['input']['value']}';
        }
      } else {
        apiResponse = 'API Error: ${res.error?.code}';
      }
    } catch (e) {
      apiResponse = 'Error: $e';
    }

    String mask(String? s) {
      if (s == null || s.isEmpty) return '-';
      if (s.length <= 8) return s;
      return '${s.substring(0, 4)}…${s.substring(s.length - 4)}';
    }

    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.black,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Logged in: $loggedInNow', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Text('Current _userAvatar: $_userAvatar', style: TextStyle(color: Colors.yellow, fontSize: 12)),
              const SizedBox(height: 6),
              Text('sessId: ${mask(sessId)}', style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
              const SizedBox(height: 6),
              Text('sessKey: ${mask(sessKey)}', style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
              const SizedBox(height: 14),
              const Text('API Response:', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(apiResponse, style: const TextStyle(color: Colors.white, fontSize: 11)),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: () async {
                  await SecureStore.clearUserSession();
                  await SecureStore.clearUserToken();
                  await SecureStore.clearUserRole();
                  await SecureStore.clearUserId();
                  if (!ctx.mounted) return;
                  Navigator.of(ctx).pop();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cleared user session')));
                  setState(() {
                    _ctx = _load();
                  });
                },
                child: const Text('Clear user session'),
              ),
            ],
          ),
        );
      },
    );
  }

  // ignore: unused_element
  Future<void> _openAnalytics(BuildContext context) async {
    final managedRes = await AnalyticsService().fetchManagedArtists();
    if (!context.mounted) return;

    String? slug;

    if (managedRes.isSuccess) {
      final items = managedRes.data!;
      if (items.isEmpty) {
        slug = await _promptArtistSlug(context);
      } else if (items.length == 1) {
        slug = items.first.slug;
      } else {
        slug = await _pickManagedArtist(context, items);
      }
    } else {
      slug = await _promptArtistSlug(context);
    }

    if (!context.mounted) return;
    if (slug == null || slug.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AnalyticsScreen(artistSlug: slug!),
      ),
    );
  }

  Future<String?> _pickManagedArtist(BuildContext context, List<ManagedArtist> items) async {
    return showDialog<String>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Select Artist'),
          children: [
            for (final a in items)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(a.slug),
                child: Text(a.name),
              ),
          ],
        );
      },
    );
  }

  Future<String?> _promptArtistSlug(BuildContext context) async {
    final controller = TextEditingController();
    final slug = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Artist Slug'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'Enter artist slug'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: const Text('Open')),
          ],
        );
      },
    );
    return slug;
  }
}

class _MenuItem {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _MenuItem(this.icon, this.title, this.color, this.onTap);
}

/// Small pill used under the profile name for role / plan labels.
class _ProfileBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const _ProfileBadge({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}
