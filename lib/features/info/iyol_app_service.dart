import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import '../../core/utils/app_logger.dart';

/// Model for iYol app data from Play Store
class IyolAppData {
  final String appName;
  final String packageName;
  final String iconUrl;
  final String rating;
  final String downloads;
  final String reviewsCount;
  final String lastUpdated;
  final bool isCached;

  IyolAppData({
    required this.appName,
    required this.packageName,
    required this.iconUrl,
    required this.rating,
    required this.downloads,
    required this.reviewsCount,
    required this.lastUpdated,
    this.isCached = false,
  });

  factory IyolAppData.fromJson(Map<String, dynamic> json) {
    return IyolAppData(
      appName: json['app_name'] ?? 'iYol App',
      packageName: json['package_name'] ?? 'com.vidmite.app',
      iconUrl: json['icon_url'] ?? '',
      rating: json['rating'] ?? '4.3',
      downloads: json['downloads'] ?? '100K+',
      reviewsCount: json['reviews_count'] ?? '10K+',
      lastUpdated: json['last_updated'] ?? DateTime.now().toIso8601String(),
      isCached: json['cached'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'app_name': appName,
    'package_name': packageName,
    'icon_url': iconUrl,
    'rating': rating,
    'downloads': downloads,
    'reviews_count': reviewsCount,
    'last_updated': lastUpdated,
    'cached': isCached,
  };
}

/// Service to fetch iYol app data from Play Store
class IyolAppService {
  static const String _apiUrl = 'https://music.hitune.in/api/';
  
  /// Fetch iYol app info from Play Store via API
  static Future<IyolAppData> fetchAppData() async {
    try {
      final response = await http.get(
        Uri.parse('${_apiUrl}?request=iyol_app_info'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['messages'] != null && data['messages'].isNotEmpty) {
          final appData = data['messages'][0];
          if (appData['ok'] != null) {
            return IyolAppData.fromJson(appData['ok']);
          }
        }
        
        // Try direct response format
        if (data['ok'] != null) {
          return IyolAppData.fromJson(data['ok']);
        }
      }
      
      // Return default if fetch fails
      return _getDefaultData();
    } catch (e) {
      if (kDebugMode) {
        AppLogger.d('[IYOL] Error fetching app data: $e');
      }
      return _getDefaultData();
    }
  }

  static IyolAppData getDefaultData() => IyolAppData(
    appName: 'iYol App',
    packageName: 'com.vidmite.app',
    iconUrl: '',
    rating: '4.3',
    downloads: '100K+',
    reviewsCount: '10K+',
    lastUpdated: DateTime.now().toIso8601String(),
    isCached: false,
  );

  static IyolAppData _getDefaultData() => getDefaultData();
}
