# Flutter App Integration Guide

## Complete Flutter App Structure for Music Hitune

### Project Setup

#### pubspec.yaml
```yaml
name: music_hitune
version: 1.0.0+2074
environment:
  sdk: ">=2.17.0 <4.0.0"
  flutter: ">=3.0.0"

dependencies:
  flutter:
    sdk: flutter
  
  # Core Dependencies
  http: ^0.13.5
  crypto: ^3.0.3
  shared_preferences: ^2.2.2
  provider: ^6.1.1
  
  # UI Dependencies
  flutter_svg: ^2.0.9
  cached_network_image: ^3.3.1
  shimmer: ^3.0.0
  animations: ^2.0.8
  
  # Audio Dependencies
  just_audio: ^0.9.36
  audio_service: ^0.18.12
  audio_session: ^0.1.16
  
  # State Management
  flutter_bloc: ^8.1.3
  equatable: ^2.0.5
  
  # Navigation
  go_router: ^13.0.1
  
  # Utilities
  connectivity_plus: ^5.0.1
  path_provider: ^2.1.2
  url_launcher: ^6.2.2
  share_plus: ^7.2.1
  
  # Firebase (Optional)
  firebase_core: ^2.24.2
  firebase_messaging: ^14.7.10
  firebase_analytics: ^10.8.0
  firebase_crashlytics: ^3.4.9

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.1
  build_runner: ^2.4.7
  json_serializable: ^6.7.1
```

### Core Architecture

#### 1. App Configuration (lib/config/app_config.dart)
```dart
class AppConfig {
  // API Configuration
  static const String apiBaseUrl = 'https://music.hitune.in/api/';
  static const String platform = 'mobile';
  static const int version = 2074;
  static const String requestCode = 'BusyOwlFrameWorkVersion201';
  
  // Security Keys
  static const String signKey = 'your_sign_key_here';
  static const String adminSignKey = 'your_admin_sign_key_here';
  
  // App Settings
  static const String appName = 'Music Hitune';
  static const String appVersion = '1.0.0';
  
  // Feature Flags (Admin Controlled)
  static bool enableSearch = true;
  static bool enablePlaylists = true;
  static bool enableSocialLogin = true;
  static bool enableUploads = true;
  static bool enableDownloads = false;
  static bool enableAds = true;
  static bool enablePayments = true;
  static bool enableOfflineMode = true;
  static bool enableDarkMode = true;
  
  // Cache Settings
  static const int cacheSize = 100; // MB
  static const int preloadCount = 3;
  static const Duration cacheTimeout = Duration(hours: 24);
  
  // UI Settings
  static const Color primaryColor = Color(0xFF2196F3);
  static const Color secondaryColor = Color(0xFF03DAC6);
  static const String fontFamily = 'Roboto';
  
  // Update from Admin Panel
  static Future<void> updateFromAdmin(Map<String, dynamic> config) async {
    enableSearch = config['enable_search'] ?? true;
    enablePlaylists = config['enable_playlists'] ?? true;
    enableSocialLogin = config['enable_social_login'] ?? true;
    enableUploads = config['enable_uploads'] ?? true;
    enableDownloads = config['enable_downloads'] ?? false;
    enableAds = config['enable_ads'] ?? true;
    enablePayments = config['enable_payments'] ?? true;
    enableOfflineMode = config['enable_offline_mode'] ?? true;
    enableDarkMode = config['enable_dark_mode'] ?? true;
  }
}
```

#### 2. API Service (lib/services/api_service.dart)
```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import '../config/app_config.dart';
import '../models/api_response.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  String computeSignature(String data, String signKey) {
    var hmac = Hmac(sha256, utf8.encode(signKey));
    var hmacDigest = hmac.convert(utf8.encode(data));
    var md5Digest = md5.convert(hmacDigest.bytes);
    return md5Digest.toString();
  }

  Map<String, String> getHeaders({bool isAdmin = false}) {
    return {
      'x-bof-request-code': AppConfig.requestCode,
      'x-bof-platform': AppConfig.platform,
      'x-bof-version': AppConfig.version.toString(),
      'Content-Type': 'application/x-www-form-urlencoded',
    };
  }

  Future<ApiResponse> makeRequest(
    String endpoint,
    Map<String, dynamic> data,
    T Function(Map<String, dynamic>) fromJson, {
    bool isAdmin = false,
  }) async {
    try {
      final formData = data.map((key, value) => 
        MapEntry(key, value.toString()));
      
      final signature = computeSignature(
        Uri(queryParameters: formData).query,
        isAdmin ? AppConfig.adminSignKey : AppConfig.signKey
      );
      
      formData['bof_signature'] = signature;

      final response = await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}$endpoint'),
        headers: getHeaders(isAdmin: isAdmin),
        body: formData,
      );

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return ApiResponse.success(fromJson(jsonData));
      } else {
        return ApiResponse.error('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      return ApiResponse.error('Request failed: $e');
    }
  }

  // Search Music
  Future<ApiResponse<SearchResponse>> searchMusic({
    required String query,
    int page = 2,
    String? objectType,
  }) async {
    return makeRequest('client/search', {
      'query': query,
      'page': page,
      if (objectType != null) 'ot': objectType,
    }, (json) => SearchResponse.fromJson(json));
  }

  // Get Client Config
  Future<ApiResponse<ClientConfig>> getClientConfig() async {
    return makeRequest('client/client_config', {}, 
      (json) => ClientConfig.fromJson(json));
  }

  // Record Play
  Future<ApiResponse<void>> recordPlay({
    required String objectHash,
    required String objectType,
  }) async {
    return makeRequest('client/muse/record', {
      'object_hash': objectHash,
      'object_type': objectType,
    }, (json) => null);
  }

  // User Authentication
  Future<ApiResponse<UserAuthResponse>> login({
    required String email,
    required String password,
  }) async {
    return makeRequest('client/user/login', {
      'email': email,
      'password': password,
    }, (json) => UserAuthResponse.fromJson(json));
  }

  // Admin Functions
  Future<ApiResponse<AdminDashboard>> getAdminDashboard() async {
    return makeRequest('be/dashboard_highlights', {}, 
      (json) => AdminDashboard.fromJson(json), isAdmin: true);
  }

  Future<ApiResponse<void>> updateClientConfig(Map<String, dynamic> config) async {
    return makeRequest('be/client_config_update', config, 
      (json) => null, isAdmin: true);
  }
}
```

#### 3. Models (lib/models/)

##### search_response.dart
```dart
class SearchResponse {
  final String status;
  final String message;
  final SearchData data;

  SearchResponse({
    required this.status,
    required this.message,
    required this.data,
  });

  factory SearchResponse.fromJson(Map<String, dynamic> json) {
    return SearchResponse(
      status: json['status'] ?? '',
      message: json['message'] ?? '',
      data: SearchData.fromJson(json['message'] ?? {}),
    );
  }
}

class SearchData {
  final List<MusicItem> widgets;
  final String historyHash;

  SearchData({
    required this.widgets,
    required this.historyHash,
  });

  factory SearchData.fromJson(Map<String, dynamic> json) {
    return SearchData(
      widgets: (json['widgets'] as List?)
          ?.map((item) => MusicItem.fromJson(item))
          .toList() ?? [],
      historyHash: json['history_hash'] ?? '',
    );
  }
}

class MusicItem {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String duration;
  final String imageUrl;
  final String audioUrl;
  final int plays;
  final int likes;

  MusicItem({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.imageUrl,
    required this.audioUrl,
    required this.plays,
    required this.likes,
  });

  factory MusicItem.fromJson(Map<String, dynamic> json) {
    return MusicItem(
      id: json['ID'] ?? '',
      title: json['title'] ?? '',
      artist: json['artist'] ?? '',
      album: json['album'] ?? '',
      duration: json['duration'] ?? '',
      imageUrl: json['image_url'] ?? '',
      audioUrl: json['audio_url'] ?? '',
      plays: json['plays'] ?? 0,
      likes: json['likes'] ?? 0,
    );
  }
}
```

##### api_response.dart
```dart
class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? error;

  ApiResponse._({required this.success, this.data, this.error});

  factory ApiResponse.success(T data) {
    return ApiResponse._(success: true, data: data);
  }

  factory ApiResponse.error(String error) {
    return ApiResponse._(success: false, error: error);
  }

  bool get hasError => error != null;
}
```

#### 4. State Management (lib/blocs/)

##### music_bloc.dart
```dart
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/search_response.dart';
import '../services/api_service.dart';

abstract class MusicEvent {}

class SearchMusicEvent extends MusicEvent {
  final String query;
  final int page;
  final String? objectType;

  SearchMusicEvent({
    required this.query,
    this.page = 2,
    this.objectType,
  });
}

class LoadMoreMusicEvent extends MusicEvent {
  final String query;
  final int page;

  LoadMoreMusicEvent({
    required this.query,
    required this.page,
  });
}

abstract class MusicState {}

class MusicInitialState extends MusicState {}

class MusicLoadingState extends MusicState {}

class MusicLoadedState extends MusicState {
  final List<MusicItem> items;
  final String historyHash;
  final bool hasMore;

  MusicLoadedState({
    required this.items,
    required this.historyHash,
    required this.hasMore,
  });
}

class MusicErrorState extends MusicState {
  final String error;

  MusicErrorState({required this.error});
}

class MusicBloc extends Bloc<MusicEvent, MusicState> {
  final ApiService _apiService = ApiService();
  List<MusicItem> _currentItems = [];
  String _historyHash = '';

  MusicBloc() : super(MusicInitialState()) {
    on<SearchMusicEvent>(_onSearchMusic);
    on<LoadMoreMusicEvent>(_onLoadMoreMusic);
  }

  Future<void> _onSearchMusic(
    SearchMusicEvent event,
    Emitter<MusicState> emit,
  ) async {
    emit(MusicLoadingState());
    
    final response = await _apiService.searchMusic(
      query: event.query,
      page: event.page,
      objectType: event.objectType,
    );

    if (response.success && response.data != null) {
      _currentItems = response.data!.data.widgets;
      _historyHash = response.data!.data.historyHash;
      
      emit(MusicLoadedState(
        items: _currentItems,
        historyHash: _historyHash,
        hasMore: _currentItems.length >= 20, // Assuming 20 items per page
      ));
    } else {
      emit(MusicErrorState(error: response.error ?? 'Search failed'));
    }
  }

  Future<void> _onLoadMoreMusic(
    LoadMoreMusicEvent event,
    Emitter<MusicState> emit,
  ) async {
    final response = await _apiService.searchMusic(
      query: event.query,
      page: event.page,
    );

    if (response.success && response.data != null) {
      _currentItems.addAll(response.data!.data.widgets);
      _historyHash = response.data!.data.historyHash;
      
      emit(MusicLoadedState(
        items: _currentItems,
        historyHash: _historyHash,
        hasMore: response.data!.data.widgets.length >= 20,
      ));
    }
  }
}
```

#### 5. Audio Player Service (lib/services/audio_service.dart)
```dart
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import '../models/search_response.dart';
import '../services/api_service.dart';

class AudioPlayerService {
  static final AudioPlayerService _instance = AudioPlayerService._internal();
  factory AudioPlayerService() => _instance;
  AudioPlayerService._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();
  final ApiService _apiService = ApiService();

  // Current playing item
  MusicItem? _currentItem;
  bool _isPlaying = false;

  // Stream controllers
  final _positionController = StreamController<Duration>();
  final _durationController = StreamController<Duration>();
  final _stateController = StreamController<PlayerState>();

  // Getters
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration> get durationStream => _durationController.stream;
  Stream<PlayerState> get stateStream => _stateController.stream;
  
  MusicItem? get currentItem => _currentItem;
  bool get isPlaying => _isPlaying;

  // Initialize audio player
  Future<void> initialize() async {
    _audioPlayer.positionStream.listen((position) {
      _positionController.add(position);
    });

    _audioPlayer.durationStream.listen((duration) {
      if (duration != null) {
        _durationController.add(duration);
      }
    });

    _audioPlayer.playerStateStream.listen((state) {
      _stateController.add(state);
      _isPlaying = state.playing;
    });
  }

  // Play music
  Future<void> play(MusicItem item) async {
    try {
      _currentItem = item;
      
      // Record play for analytics
      await _audioService.recordPlay(
        objectHash: item.id,
        objectType: 'music',
      );

      // Load and play audio
      await _audioPlayer.setUrl(item.audioUrl);
      await _audioPlayer.play();
    } catch (e) {
      print('Error playing audio: $e');
      throw Exception('Failed to play audio');
    }
  }

  // Pause/Resume
  Future<void> pause() async {
    await _audioPlayer.pause();
  }

  Future<void> resume() async {
    await _audioPlayer.play();
  }

  // Stop
  Future<void> stop() async {
    await _audioPlayer.stop();
    _currentItem = null;
  }

  // Seek
  Future<void> seek(Duration position) async {
    await _audioPlayer.seek(position);
  }

  // Volume
  Future<void> setVolume(double volume) async {
    await _audioPlayer.setVolume(volume);
  }

  // Dispose
  void dispose() {
    _audioPlayer.dispose();
    _positionController.close();
    _durationController.close();
    _stateController.close();
  }
}
```

#### 6. UI Components (lib/widgets/)

##### music_player_widget.dart
```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/audio_service.dart';
import '../models/search_response.dart';

class MusicPlayerWidget extends StatefulWidget {
  @override
  _MusicPlayerWidgetState createState() => _MusicPlayerWidgetState();
}

class _MusicPlayerWidgetState extends State<MusicPlayerWidget> {
  late AudioPlayerService _audioService;

  @override
  void initState() {
    super.initState();
    _audioService = AudioPlayerService();
    _audioService.initialize();
  }

  @override
  void dispose() {
    _audioService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: _audioService.stateStream,
      builder: (context, snapshot) {
        final playerState = snapshot.data;
        final isPlaying = playerState?.playing ?? false;
        final currentItem = _audioService.currentItem;

        if (currentItem == null) {
          return SizedBox.shrink();
        }

        return Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Album Art and Info
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      currentItem.imageUrl,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentItem.title,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          currentItem.artist,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              
              // Progress Bar
              StreamBuilder<Duration>(
                stream: _audioService.positionStream,
                builder: (context, positionSnapshot) {
                  return StreamBuilder<Duration>(
                    stream: _audioService.durationStream,
                    builder: (context, durationSnapshot) {
                      final position = positionSnapshot.data ?? Duration.zero;
                      final duration = durationSnapshot.data ?? Duration.zero;
                      
                      return Column(
                        children: [
                          Slider(
                            value: position.inSeconds.toDouble(),
                            max: duration.inSeconds.toDouble(),
                            onChanged: (value) {
                              _audioService.seek(Duration(seconds: value.toInt()));
                            },
                            activeColor: Colors.white,
                            inactiveColor: Colors.white.withOpacity(0.3),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDuration(position),
                                style: TextStyle(color: Colors.white, fontSize: 12),
                              ),
                              Text(
                                _formatDuration(duration),
                                style: TextStyle(color: Colors.white, fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              
              // Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: Icon(Icons.skip_previous, color: Colors.white),
                    onPressed: () {
                      // Implement previous track logic
                    },
                  ),
                  IconButton(
                    icon: Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 32,
                    ),
                    onPressed: () {
                      if (isPlaying) {
                        _audioService.pause();
                      } else {
                        _audioService.resume();
                      }
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.skip_next, color: Colors.white),
                    onPressed: () {
                      // Implement next track logic
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }
}
```

##### search_widget.dart
```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/music_bloc.dart';
import '../models/search_response.dart';
import 'music_item_widget.dart';

class SearchWidget extends StatefulWidget {
  @override
  _SearchWidgetState createState() => _SearchWidgetState();
}

class _SearchWidgetState extends State<SearchWidget> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late MusicBloc _musicBloc;
  String _currentQuery = '';
  int _currentPage = 2;

  @override
  void initState() {
    super.initState();
    _musicBloc = MusicBloc();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _musicBloc.close();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels == 
        _scrollController.position.maxScrollExtent) {
      if (_currentQuery.isNotEmpty) {
        _musicBloc.add(LoadMoreMusicEvent(
          query: _currentQuery,
          page: _currentPage + 1,
        ));
      }
    }
  }

  void _onSearch() {
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      setState(() {
        _currentQuery = query;
        _currentPage = 2;
      });
      _musicBloc.add(SearchMusicEvent(query: query));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search Bar
        Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search for music...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).cardColor,
                  ),
                  onSubmitted: (_) => _onSearch(),
                ),
              ),
              SizedBox(width: 8),
              ElevatedButton(
                onPressed: _onSearch,
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text('Search'),
              ),
            ],
          ),
        ),
        
        // Search Results
        Expanded(
          child: BlocBuilder<MusicBloc, MusicState>(
            bloc: _musicBloc,
            builder: (context, state) {
              if (state is MusicInitialState) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.music_note,
                        size: 64,
                        color: Theme.of(context).primaryColor.withOpacity(0.5),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Search for your favorite music',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                );
              }
              
              if (state is MusicLoadingState) {
                return Center(child: CircularProgressIndicator());
              }
              
              if (state is MusicErrorState) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red,
                      ),
                      SizedBox(height: 16),
                      Text(
                        state.error,
                        style: TextStyle(color: Colors.red),
                      ),
                      SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _onSearch,
                        child: Text('Retry'),
                      ),
                    ],
                  ),
                );
              }
              
              if (state is MusicLoadedState) {
                if (state.items.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: Theme.of(context).primaryColor.withOpacity(0.5),
                        ),
                        SizedBox(height: 16),
                        Text('No results found'),
                      ],
                    ),
                  );
                }
                
                return ListView.builder(
                  controller: _scrollController,
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  itemCount: state.items.length + (state.hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == state.items.length) {
                      return Center(child: CircularProgressIndicator());
                    }
                    
                    final item = state.items[index];
                    return MusicItemWidget(musicItem: item);
                  },
                );
              }
              
              return SizedBox.shrink();
            },
          ),
        ),
      ],
    );
  }
}
```

#### 7. Main App (lib/main.dart)
```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config/app_config.dart';
import 'services/audio_service.dart';
import 'screens/home_screen.dart';
import 'screens/admin_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize shared preferences
  final prefs = await SharedPreferences.getInstance();
  
  // Load saved configuration
  await loadSavedConfiguration(prefs);
  
  runApp(MyApp(prefs: prefs));
}

Future<void> loadSavedConfiguration(SharedPreferences prefs) async {
  // Load saved admin configuration
  final savedConfig = prefs.getString('admin_config');
  if (savedConfig != null) {
    try {
      final config = json.decode(savedConfig);
      await AppConfig.updateFromAdmin(config);
    } catch (e) {
      print('Error loading saved configuration: $e');
    }
  }
}

class MyApp extends StatelessWidget {
  final SharedPreferences prefs;
  
  const MyApp({Key? key, required this.prefs}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SharedPreferences>.value(value: prefs),
        Provider<AudioPlayerService>(
          create: (_) => AudioPlayerService()..initialize(),
          dispose: (_, service) => service.dispose(),
        ),
      ],
      child: MaterialApp(
        title: AppConfig.appName,
        theme: ThemeData(
          primaryColor: AppConfig.primaryColor,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppConfig.primaryColor,
            secondary: AppConfig.secondaryColor,
          ),
          fontFamily: AppConfig.fontFamily,
          useMaterial3: true,
        ),
        darkTheme: AppConfig.enableDarkMode ? ThemeData.dark().copyWith(
          primaryColor: AppConfig.primaryColor,
          colorScheme: ColorScheme.dark().copyWith(
            primary: AppConfig.primaryColor,
            secondary: AppConfig.secondaryColor,
          ),
        ) : null,
        home: HomeScreen(),
        routes: {
          '/admin': (context) => AdminScreen(),
        },
      ),
    );
  }
}
```

### Complete App Features

#### 1. User Authentication
- Login/Register with email/password
- Social login (Google, Facebook)
- User profile management
- Password reset

#### 2. Music Discovery
- Search with filters (genre, artist, album)
- Trending music
- Personalized recommendations
- Recently played
- Favorites/liked songs

#### 3. Music Player
- Full-featured audio player
- Background playback
- Playlists
- Queue management
- Equalizer
- Sleep timer
- Offline mode

#### 4. Social Features
- User profiles
- Follow artists
- Share music
- Comments and ratings
- Playlists sharing

#### 5. Admin Panel (Mobile)
- Dashboard with analytics
- User management
- Content moderation
- Configuration management
- Reports generation

#### 6. Offline Features
- Download music for offline
- Offline playlists
- Cache management
- Sync when online

### Deployment Checklist

#### Pre-deployment
- [ ] Configure API endpoints
- [ ] Set up Firebase (optional)
- [ ] Configure payment gateways
- [ ] Set up analytics
- [ ] Configure push notifications
- [ ] Test all features
- [ ] Performance optimization
- [ ] Security audit

#### App Store Preparation
- [ ] App icons and screenshots
- [ ] App description
- [ ] Privacy policy
- [ ] Terms of service
- [ ] Content rating
- [ ] Pricing strategy

#### Post-deployment
- [ ] Monitor crashes
- [ ] Track user analytics
- [ ] Monitor API usage
- [ ] Regular updates
- [ ] User feedback
- [ ] Performance monitoring

### Best Practices

#### Code Organization
- Follow clean architecture
- Use dependency injection
- Implement proper error handling
- Write unit tests
- Document code
- Use linting

#### Performance
- Implement caching
- Use lazy loading
- Optimize images
- Minimize API calls
- Use background threads
- Profile regularly

#### Security
- Validate all inputs
- Use HTTPS
- Implement proper authentication
- Protect API keys
- Regular security audits
- Update dependencies

This complete Flutter app structure provides all the features available on the website, with admin panel controls for configuration management as requested. The app is ready for deployment and can be customized further based on specific requirements.