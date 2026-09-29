# Music.hitune.in Flutter API Documentation

## Overview
Complete API documentation for building Flutter applications with music.hitune.in platform. This documentation covers all endpoints, authentication, and integration patterns specifically designed for Flutter development.

## Base Configuration

### API Base URL
```
https://music.hitune.in/api/
```

### Required Headers for All Requests
```dart
Headers: {
  'x-bof-r![img.png](img.png)equest-code': 'BusyOwlFrameWorkVersion201',
  'x-bof-platform': 'mobile',
  'x-bof-version': '2074',
  'Content-Type': 'application/x-www-form-urlencoded'
}
```

### API Signing (Required for All Requests)
Every API request must be signed using HMAC-SHA256 + MD5:

```dart
import 'dart:convert';
import 'package:crypto/crypto.dart';

String computeSignature(String data, String signKey) {
  // HMAC-SHA256
  var hmac = Hmac(sha256, utf8.encode(signKey));
  var hmacDigest = hmac.convert(utf8.encode(data));
  
  // MD5 of HMAC result
  var md5Digest = md5.convert(hmacDigest.bytes);
  
  return md5Digest.toString();
}
```

## Authentication & User Management

### 1. User Authentication
**Endpoint:** `POST /client/user_auth`

**Flutter Implementation:**
```dart
Future<Map<String, dynamic>> authenticateUser(String username, String password) async {
  var formData = {
    'username': username,
    'password': password,
  };
  
  var signature = computeSignature(Uri(queryParameters: formData).query, signKey);
  formData['bof_signature'] = signature;
  
  var response = await http.post(
    Uri.parse('https://music.hitune.in/api/client/user_auth'),
    headers: {
      'x-bof-request-code': 'BusyOwlFrameWorkVersion201',
      'x-bof-platform': 'mobile',
      'x-bof-version': '2074',
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: formData,
  );
  
  return json.decode(response.body);
}
```
 

## Music Discovery & Search

### 3. Search Music
**Endpoint:** `POST /client/search`

**Parameters:**
- `query` (string): Search query
- `page` (int): Page number (min: 2)
- `ot` (string, optional): Object type filter

**Flutter Implementation:**
```dart
class SearchService {
  static Future<SearchResponse> searchMusic({
    required String query,
    required int page,
    String? objectType,
  }) async {
    var formData = {
      'query': query,
      'page': page.toString(),
    };
    
    if (objectType != null) {
      formData['ot'] = objectType;
    }
    
    var signature = computeSignature(Uri(queryParameters: formData).query, signKey);
    formData['bof_signature'] = signature;
    
    var response = await http.post(
      Uri.parse('https://music.hitune.in/api/client/search'),
      headers: getHeaders(),
      body: formData,
    );
    
    return SearchResponse.fromJson(json.decode(response.body));
  }
}

class SearchResponse {
  final String status;
  final List<MusicItem> widgets;
  final String? history;
  
  SearchResponse.fromJson(Map<String, dynamic> json)
      : status = json['status'],
        widgets = (json['message']['widgets'] as List)
            .map((item) => MusicItem.fromJson(item))
            .toList(),
        history = json['message']['history'];
}

class MusicItem {
  final String id;
  final String title;
  final String artist;
  final String? coverArt;
  final String? duration;
  final String hash;
  
  MusicItem.fromJson(Map<String, dynamic> json)
      : id = json['ID']?.toString() ?? '',
        title = json['title'] ?? '',
        artist = json['artist'] ?? '',
        coverArt = json['cover'],
        duration = json['duration'],
        hash = json['hash'] ?? '';
}
```

### 4. Search Suggestions
**Endpoint:** `POST /client/searchSuggs`

**Flutter Implementation:**
```dart
Future<List<String>> getSearchSuggestions(String query) async {
  var formData = {'query': query};
  
  var signature = computeSignature(Uri(queryParameters: formData).query, signKey);
  formData['bof_signature'] = signature;
  
  var response = await http.post(
    Uri.parse('https://music.hitune.in/api/client/searchSuggs'),
    headers: getHeaders(),
    body: formData,
  );
  
  var data = json.decode(response.body);
  return List<String>.from(data['message'] ?? []);
}
```

## Music Playback & Tracking

### 5. Record Music Play
**Endpoint:** `POST /client/muse_record`

**Parameters:**
- `object_type` (string): Type of music object
- `object_hash` (string): MD5 hash of the music item

**Flutter Implementation:**
```dart
Future<void> recordMusicPlay(String objectType, String objectHash) async {
  var formData = {
    'object_type': objectType,
    'object_hash': objectHash,
  };
  
  var signature = computeSignature(Uri(queryParameters: formData).query, signKey);
  formData['bof_signature'] = signature;
  
  await http.post(
    Uri.parse('https://music.hitune.in/api/client/muse_record'),
    headers: getHeaders(),
    body: formData,
  );
}
```

### 6. Stream Music Headers
**Endpoint:** `POST /client/muse_stream_heads`

**Flutter Implementation:**
```dart
Future<StreamHeaders> getStreamHeaders(String objectHash) async {
  var formData = {'object_hash': objectHash};
  
  var signature = computeSignature(Uri(queryParameters: formData).query, signKey);
  formData['bof_signature'] = signature;
  
  var response = await http.post(
    Uri.parse('https://music.hitune.in/api/client/muse_stream_heads'),
    headers: getHeaders(),
    body: formData,
  );
  
  return StreamHeaders.fromJson(json.decode(response.body));
}
```

## Playlist Management

### 7. Create Playlist
**Endpoint:** `POST /client/playlist_create`

**Flutter Implementation:**
```dart
Future<bool> createPlaylist(String name, String? objectType, String? objectHash) async {
  var formData = {
    'playlist': name,
  };
  
  if (objectType != null) formData['object_type'] = objectType;
  if (objectHash != null) formData['object'] = objectHash;
  
  var signature = computeSignature(Uri(queryParameters: formData).query, signKey);
  formData['bof_signature'] = signature;
  
  var response = await http.post(
    Uri.parse('https://music.hitune.in/api/client/playlist_create'),
    headers: getHeaders(),
    body: formData,
  );
  
  var data = json.decode(response.body);
  return data['status'] == 'ok';
}
```

### 8. Get User Playlists
**Endpoint:** `POST /client/user_library`

**Flutter Implementation:**
```dart
Future<List<Playlist>> getUserPlaylists() async {
  var formData = <String, String>{};
  
  var signature = computeSignature(Uri(queryParameters: formData).query, signKey);
  formData['bof_signature'] = signature;
  
  var response = await http.post(
    Uri.parse('https://music.hitune.in/api/client/user_library'),
    headers: getHeaders(),
    body: formData,
  );
  
  var data = json.decode(response.body);
  return (data['message']['playlists'] as List)
      .map((item) => Playlist.fromJson(item))
      .toList();
}
```

## User Engagement

### 9. Like/Unlike Music
**Endpoint:** `POST /client/like` / `POST /client/unlike`

**Flutter Implementation:**
```dart
Future<bool> toggleLike(String objectType, String objectHash, bool isLiked) async {
  var endpoint = isLiked ? 'unlike' : 'like';
  var formData = {
    'object_type': objectType,
    'object_hash': objectHash,
  };
  
  var signature = computeSignature(Uri(queryParameters: formData).query, signKey);
  formData['bof_signature'] = signature;
  
  var response = await http.post(
    Uri.parse('https://music.hitune.in/api/client/$endpoint'),
    headers: getHeaders(),
    body: formData,
  );
  
  var data = json.decode(response.body);
  return data['status'] == 'ok';
}
```

### 10. Subscribe/Unsubscribe
**Endpoint:** `POST /client/subscribe` / `POST /client/unsubscribe`

**Flutter Implementation:**
```dart
Future<bool> toggleSubscription(String objectType, String objectHash) async {
  var formData = {
    'object_type': objectType,
    'object_hash': objectHash,
  };
  
  var signature = computeSignature(Uri(queryParameters: formData).query, signKey);
  formData['bof_signature'] = signature;
  
  var response = await http.post(
    Uri.parse('https://music.hitune.in/api/client/subscribe'),
    headers: getHeaders(),
    body: formData,
  );
  
  var data = json.decode(response.body);
  return data['status'] == 'ok';
}
```

## User Account Management

### 11. User Profile Edit
**Endpoint:** `POST /client/user_edit`

**Flutter Implementation:**
```dart
Future<bool> updateUserProfile(Map<String, dynamic> profileData) async {
  var formData = profileData.map((key, value) => MapEntry(key, value.toString()));
  
  var signature = computeSignature(Uri(queryParameters: formData).query, signKey);
  formData['bof_signature'] = signature;
  
  var response = await http.post(
    Uri.parse('https://music.hitune.in/api/client/user_edit'),
    headers: getHeaders(),
    body: formData,
  );
  
  var data = json.decode(response.body);
  return data['status'] == 'ok';
}
```

### 12. User Upload Configuration
**Endpoint:** `POST /client/user_upload_config`

**Flutter Implementation:**
```dart
Future<UploadConfig> getUploadConfig() async {
  var formData = <String, String>{};
  
  var signature = computeSignature(Uri(queryParameters: formData).query, signKey);
  formData['bof_signature'] = signature;
  
  var response = await http.post(
    Uri.parse('https://music.hitune.in/api/client/user_upload_config'),
    headers: getHeaders(),
    body: formData,
  );
  
  return UploadConfig.fromJson(json.decode(response.body));
}
```

## Client Configuration

### 13. Get Client Config
**Endpoint:** `POST /client/client_config`

**Flutter Implementation:**
```dart
Future<ClientConfig> getClientConfig() async {
  var formData = <String, String>{};
  
  var signature = computeSignature(Uri(queryParameters: formData).query, signKey);
  formData['bof_signature'] = signature;
  
  var response = await http.post(
    Uri.parse('https://music.hitune.in/api/client/client_config'),
    headers: getHeaders(),
    body: formData,
  );
  
  return ClientConfig.fromJson(json.decode(response.body));
}
```

### 14. Get Translations
**Endpoint:** `POST /client/client_translations`

**Flutter Implementation:**
```dart
Future<Map<String, String>> getTranslations() async {
  var formData = <String, String>{};
  
  var signature = computeSignature(Uri(queryParameters: formData).query, signKey);
  formData['bof_signature'] = signature;
  
  var response = await http.post(
    Uri.parse('https://music.hitune.in/api/client/client_translations'),
    headers: getHeaders(),
    body: formData,
  );
  
  var data = json.decode(response.body);
  return Map<String, String>.from(data['message'] ?? {});
}
```

## Payment & Monetization

### 15. Payment Check
**Endpoint:** `POST /client/payment_check`

**Flutter Implementation:**
```dart
Future<PaymentStatus> checkPayment(String paymentId) async {
  var formData = {'payment_id': paymentId};
  
  var signature = computeSignature(Uri(queryParameters: formData).query, signKey);
  formData['bof_signature'] = signature;
  
  var response = await http.post(
    Uri.parse('https://music.hitune.in/api/client/payment_check'),
    headers: getHeaders(),
    body: formData,
  );
  
  return PaymentStatus.fromJson(json.decode(response.body));
}
```

### 16. Purchase Subscription
**Endpoint:** `POST /client/purchase_subs_plan`

**Flutter Implementation:**
```dart
Future<bool> purchaseSubscription(String planId, String objectType, String objectHash) async {
  var formData = {
    'plan_id': planId,
    'object_type': objectType,
    'object_hash': objectHash,
  };
  
  var signature = computeSignature(Uri(queryParameters: formData).query, signKey);
  formData['bof_signature'] = signature;
  
  var response = await http.post(
    Uri.parse('https://music.hitune.in/api/client/purchase_subs_plan'),
    headers: getHeaders(),
    body: formData,
  );
  
  var data = json.decode(response.body);
  return data['status'] == 'ok';
}
```

## Admin Panel Features (For Admin App)

### 17. Admin Login
**Endpoint:** `POST /be/login`

**Flutter Implementation:**
```dart
Future<Map<String, dynamic>> adminLogin(String username, String password) async {
  var formData = {
    'username': username,
    'password': password,
  };
  
  var signature = computeSignature(Uri(queryParameters: formData).query, adminSignKey);
  formData['bof_signature'] = signature;
  
  var response = await http.post(
    Uri.parse('https://music.hitune.in/api/be/login'),
    headers: getAdminHeaders(),
    body: formData,
  );
  
  return json.decode(response.body);
}
```

### 18. Get Dashboard Highlights
**Endpoint:** `POST /be/dashboard_highlights`

**Flutter Implementation:**
```dart
Future<DashboardData> getDashboardHighlights() async {
  var formData = <String, String>{};
  
  var signature = computeSignature(Uri(queryParameters: formData).query, adminSignKey);
  formData['bof_signature'] = signature;
  
  var response = await http.post(
    Uri.parse('https://music.hitune.in/api/be/dashboard_highlights'),
    headers: getAdminHeaders(),
    body: formData,
  );
  
  return DashboardData.fromJson(json.decode(response.body));
}
```

### 19. Admin Stats
**Endpoint:** `POST /be/stats`

**Flutter Implementation:**
```dart
Future<AdminStats> getAdminStats() async {
  var formData = <String, String>{};
  
  var signature = computeSignature(Uri(queryParameters: formData).query, adminSignKey);
  formData['bof_signature'] = signature;
  
  var response = await http.post(
    Uri.parse('https://music.hitune.in/api/be/stats'),
    headers: getAdminHeaders(),
    body: formData,
  );
  
  return AdminStats.fromJson(json.decode(response.body));
}
```

### 20. Client Configuration Management
**Endpoint:** `POST /be/client_config`

**Flutter Implementation:**
```dart
Future<bool> updateClientConfig(Map<String, dynamic> config) async {
  var formData = config.map((key, value) => MapEntry(key, value.toString()));
  
  var signature = computeSignature(Uri(queryParameters: formData).query, adminSignKey);
  formData['bof_signature'] = signature;
  
  var response = await http.post(
    Uri.parse('https://music.hitune.in/api/be/client_config'),
    headers: getAdminHeaders(),
    body: formData,
  );
  
  var data = json.decode(response.body);
  return data['status'] == 'ok';
}
```

## Error Handling

### Standard Error Response
```dart
class ApiError {
  final String status;
  final String error;
  final Map<String, dynamic>? details;
  
  ApiError.fromJson(Map<String, dynamic> json)
      : status = json['status'],
        error = json['error'],
        details = json['details'];
}
```

### Error Handling in Flutter
```dart
Future<T> handleApiResponse<T>(
  Future<http.Response> Function() apiCall,
  T Function(Map<String, dynamic>) parser,
) async {
  try {
    var response = await apiCall();
    var data = json.decode(response.body);
    
    if (data['status'] == 'ok') {
      return parser(data);
    } else {
      throw ApiException.fromJson(data);
    }
  } catch (e) {
    if (e is ApiException) {
      rethrow;
    } else {
      throw ApiException('network_error', 'Network request failed');
    }
  }
}

class ApiException implements Exception {
  final String code;
  final String message;
  
  ApiException(this.code, this.message);
  
  factory ApiException.fromJson(Map<String, dynamic> json) {
    return ApiException(
      json['error'] ?? 'unknown_error',
      json['message'] ?? 'Unknown error occurred',
    );
  }
  
  @override
  String toString() => 'ApiException: $code - $message';
}
```

## Admin Panel Configuration Options

### Available Admin Controls:
1. **Client Configuration**
   - App settings
   - Theme management
   - Language settings
   - Currency settings

2. **User Management**
   - User roles and permissions
   - Subscription plans
   - Payment settings

3. **Content Management**
   - Music upload settings
   - Content moderation
   - Playlist management

4. **Analytics & Statistics**
   - Dashboard highlights
   - User statistics
   - Revenue tracking

5. **System Settings**
   - API configuration
   - Security settings
   - Storage configuration

## Flutter Integration Best Practices

### 1. Service Architecture
```dart
// lib/services/api_service.dart
class ApiService {
  static const String baseUrl = 'https://music.hitune.in/api/';
  static const String signKey = 'your_sign_key_here';
  
  static Map<String, String> getHeaders() => {
    'x-bof-request-code': 'BusyOwlFrameWorkVersion201',
    'x-bof-platform': 'mobile',
    'x-bof-version': '2074',
    'Content-Type': 'application/x-www-form-urlencoded',
  };
  
  static Future<T> makeRequest<T>(
    String endpoint,
    Map<String, String> data,
    T Function(Map<String, dynamic>) parser,
  ) async {
    var signature = computeSignature(Uri(queryParameters: data).query, signKey);
    data['bof_signature'] = signature;
    
    var response = await http.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: getHeaders(),
      body: data,
    );
    
    return handleApiResponse(() => Future.value(response), parser);
  }
}
```

### 2. State Management with Provider
```dart
// lib/providers/music_provider.dart
class MusicProvider with ChangeNotifier {
  List<MusicItem> _searchResults = [];
  bool _isLoading = false;
  String? _error;
  
  List<MusicItem> get searchResults => _searchResults;
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  Future<void> searchMusic(String query, int page) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      var response = await SearchService.searchMusic(
        query: query,
        page: page,
      );
      _searchResults = response.widgets;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
```

### 3. Audio Player Integration
```dart
// lib/services/audio_player_service.dart
class AudioPlayerService {
  static final AudioPlayer _audioPlayer = AudioPlayer();
  
  static Future<void> playMusic(MusicItem music) async {
    // Get stream headers first
    var streamHeaders = await getStreamHeaders(music.hash);
    
    // Play the music
    await _audioPlayer.play(streamHeaders.streamUrl);
    
    // Record the play
    await recordMusicPlay('music', music.hash);
  }
  
  static Future<void> pause() => _audioPlayer.pause();
  static Future<void> resume() => _audioPlayer.resume();
  static Future<void> stop() => _audioPlayer.stop();
}
```

### 4. Offline Caching
```dart
// lib/services/cache_service.dart
class CacheService {
  static const String searchCacheKey = 'search_results';
  static const Duration cacheDuration = Duration(hours: 1);
  
  static Future<void> cacheSearchResults(String query, List<MusicItem> results) async {
    var prefs = await SharedPreferences.getInstance();
    var cacheData = {
      'timestamp': DateTime.now().toIso8601String(),
      'results': results.map((item) => item.toJson()).toList(),
    };
    await prefs.setString('$searchCacheKey-$query', json.encode(cacheData));
  }
  
  static Future<List<MusicItem>?> getCachedSearchResults(String query) async {
    var prefs = await SharedPreferences.getInstance();
    var cachedData = prefs.getString('$searchCacheKey-$query');
    
    if (cachedData != null) {
      var data = json.decode(cachedData);
      var timestamp = DateTime.parse(data['timestamp']);
      
      if (DateTime.now().difference(timestamp) < cacheDuration) {
        return (data['results'] as List)
            .map((item) => MusicItem.fromJson(item))
            .toList();
      }
    }
    
    return null;
  }
}
```

## Complete Flutter App Structure

```
lib/
├── main.dart
├── config/
│   └── app_config.dart
├── models/
│   ├── music_item.dart
│   ├── playlist.dart
│   ├── user.dart
│   └── api_responses.dart
├── services/
│   ├── api_service.dart
│   ├── auth_service.dart
│   ├── audio_player_service.dart
│   ├── cache_service.dart
│   └── playlist_service.dart
├── providers/
│   ├── auth_provider.dart
│   ├── music_provider.dart
│   └── playlist_provider.dart
├── screens/
│   ├── auth/
│   │   ├── login_screen.dart
│   │   └── register_screen.dart
│   ├── home/
│   │   ├── home_screen.dart
│   │   └── search_screen.dart
│   ├── music/
│   │   ├── music_player_screen.dart
│   │   └── playlist_screen.dart
│   └── profile/
│       └── profile_screen.dart
├── widgets/
│   ├── music_card.dart
│   ├── playlist_card.dart
│   └── player_controls.dart
└── utils/
    ├── constants.dart
    └── helpers.dart
```

## Security Notes

1. **Sign Key Management**: Store sign key securely using flutter_secure_storage
2. **User Session**: Implement proper session management
3. **API Rate Limiting**: Implement request throttling
4. **Data Validation**: Always validate user input
5. **HTTPS Only**: Ensure all API calls use HTTPS

## Testing

### Unit Tests
```dart
// test/services/api_service_test.dart
void main() {
  group('ApiService', () {
    test('should compute signature correctly', () {
      var signature = ApiService.computeSignature('test=data', 'test-key');
      expect(signature, isNotNull);
      expect(signature.length, equals(32)); // MD5 length
    });
    
    test('should handle successful API response', () async {
      var response = await ApiService.makeRequest('client/search', {
        'query': 'test',
        'page': '2',
      }, SearchResponse.fromJson);
      
      expect(response, isA<SearchResponse>());
    });
  });
}
```

## Deployment Checklist

- [ ] Configure production sign key
- [ ] Set up proper error handling
- [ ] Implement offline caching
- [ ] Add push notifications
- [ ] Configure app signing
- [ ] Set up analytics
- [ ] Implement proper logging
- [ ] Add crash reporting
- [ ] Test on multiple devices
- [ ] Performance optimization

## Support

For API support and questions:
- Base URL: https://music.hitune.in/api/
- Framework: BusyOwlFramework v2074
- Platform: Mobile (Flutter)
- Version: 2074

---

**Note**: This documentation is specifically designed for Flutter development and includes all necessary authentication, error handling, and best practices for building a complete music streaming application.