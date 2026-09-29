class AppModel {
  final String name;
  final String icon;
  final double rating;
  final String downloads;
  final String url;

  AppModel({
    required this.name,
    required this.icon,
    required this.rating,
    required this.downloads,
    required this.url,
  });

  factory AppModel.fromJson(Map<String, dynamic> json) {
    final ratingValue = json['rating'];
    final nameValue = json['name']?.toString().trim() ?? '';
    final iconValue = json['icon']?.toString().trim() ?? '';
    
    return AppModel(
      name: nameValue.isNotEmpty ? nameValue : 'Unknown App',
      icon: iconValue.isNotEmpty ? iconValue : 'https://via.placeholder.com/56',
      rating: ratingValue != null ? double.tryParse(ratingValue.toString()) ?? (ratingValue is num ? ratingValue.toDouble() : 0.0) : 0.0,
      downloads: json['downloads']?.toString() ?? '0',
      url: json['url']?.toString() ?? '#',
    );
  }
}
