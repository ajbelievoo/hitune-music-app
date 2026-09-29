import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_model.dart';

class OtherProjectsService {
  static const String _apiUrl = 'https://music.hitune.in/api/other_apps_list_public';

  static Future<List<AppModel>> fetchApps() async {
    try {
      final response = await http.get(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final dynamic jsonData = json.decode(response.body);
        
        // Check if the response has an 'items' field that contains the list
        if (jsonData is Map<String, dynamic> && jsonData.containsKey('items') && jsonData['items'] is List) {
          final List<dynamic> appsData = jsonData['items'];
          return appsData.map((json) => AppModel.fromJson(json as Map<String, dynamic>)).toList();
        } else if (jsonData is List) {
          // If the response is directly a list
          return jsonData.map((json) => AppModel.fromJson(json as Map<String, dynamic>)).toList();
        } else {
          throw Exception('Invalid response format: expected list or object with items field');
        }
      } else {
        throw Exception('Failed to load apps: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching apps: $e');
    }
  }
}
