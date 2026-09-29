# Admin Panel Configuration Guide

## Overview
Complete guide for configuring admin panel controls and settings for the music.hitune.in platform. This document covers all configurable options that can be managed through the admin panel.

## Admin Panel Access
- **URL**: https://music.hitune.in/api/be/
- **Authentication**: Requires admin login with proper permissions
- **API Version**: 2074
- **Framework**: BusyOwlFramework

## Configuration Categories

### 1. Client Configuration Management

#### App Settings
```php
// Configurable via: /api/be/client_config

// App Information
- app_name: "Music Hitune"
- app_description: "Your music streaming platform"
- app_version: "2074"
- app_language: "en" // Supported: en, es, fr, de, hi

// UI Settings
- theme_primary_color: "#FF6B35"
- theme_secondary_color: "#004E89"
- app_logo_url: "https://music.hitune.in/assets/logo.png"
- favicon_url: "https://music.hitune.in/assets/favicon.ico"

// Feature Toggles
- enable_search: true
- enable_playlists: true
- enable_social_login: true
- enable_uploads: true
- enable_downloads: false
- enable_ads: true
- enable_payments: true
```

#### Flutter App Configuration
```dart
// Admin can configure these settings for Flutter app
class AppConfig {
  static const String appName = "Music Hitune";
  static const String appVersion = "2074";
  static const String apiBaseUrl = "https://music.hitune.in/api/";
  static const String platform = "mobile";
  static const int version = 2074;
  
  // Feature flags from admin panel
  static bool enableSearch = true;
  static bool enablePlaylists = true;
  static bool enableSocialLogin = true;
  static bool enableUploads = true;
  static bool enableDownloads = false;
  static bool enableAds = true;
  static bool enablePayments = true;
}
```

### 2. User Management Configuration

#### User Registration Settings
```php
// Configurable options:
- allow_registration: true
- email_verification_required: true
- phone_verification_required: false
- social_login_enabled: true
- manual_approval_required: false
- registration_email_domain_restrictions: [] // Empty = all domains allowed
- minimum_age_required: 13
- captcha_enabled: true
```

#### User Roles & Permissions
```php
// User Groups (Configurable)
$userGroups = [
    'guest' => [
        'can_search' => true,
        'can_play' => true,
        'can_create_playlists' => false,
        'can_upload' => false,
        'can_download' => false,
        'ads_enabled' => true
    ],
    'user' => [
        'can_search' => true,
        'can_play' => true,
        'can_create_playlists' => true,
        'can_upload' => true,
        'can_download' => false,
        'ads_enabled' => true
    ],
    'premium' => [
        'can_search' => true,
        'can_play' => true,
        'can_create_playlists' => true,
        'can_upload' => true,
        'can_download' => true,
        'ads_enabled' => false
    ],
    'admin' => [
        'can_search' => true,
        'can_play' => true,
        'can_create_playlists' => true,
        'can_upload' => true,
        'can_download' => true,
        'ads_enabled' => false,
        'can_manage_users' => true,
        'can_manage_content' => true,
        'can_view_analytics' => true
    ]
];
```

### 3. Content Management Configuration

#### Music Upload Settings
```php
// Upload Configuration
- max_upload_size: "100MB" // Per file
- allowed_audio_formats: ["mp3", "wav", "flac", "m4a", "ogg"]
- max_daily_uploads_per_user: 10
- upload_requires_approval: true
- auto_tagging_enabled: true
- duplicate_detection_enabled: true
- copyright_check_enabled: true

// Quality Settings
- audio_quality_options: ["128kbps", "192kbps", "320kbps", "lossless"]
- default_quality: "192kbps"
- allow_user_quality_selection: true
```

#### Content Moderation
```php
// Moderation Settings
- profanity_filter_enabled: true
- auto_moderation_enabled: true
- manual_review_required: true
- community_guidelines_url: "https://music.hitune.in/guidelines"
- report_threshold_for_review: 5
- automatic_removal_threshold: 10
```

### 4. Search & Discovery Configuration

#### Search Settings
```php
// Search Configuration
- search_algorithm: "relevance" // relevance, popularity, date
- enable_search_suggestions: true
- search_suggestion_limit: 10
- fuzzy_search_enabled: true
- search_history_enabled: true
- personalisation_enabled: true

// Filter Options
- enable_genre_filter: true
- enable_artist_filter: true
- enable_album_filter: true
- enable_year_filter: true
- enable_duration_filter: true
```

#### Recommendation Engine
```php
// Recommendation Settings
- recommendation_algorithm: "collaborative_filtering"
- trending_calculation_period: "7days"
- user_history_weight: 0.7
- popularity_weight: 0.3
- minimum_plays_for_trending: 100
- refresh_recommendations_daily: true
```

### 5. Monetization Configuration

#### Subscription Plans
```php
// Subscription Plans (Admin Configurable)
$subscriptionPlans = [
    'free' => [
        'name' => 'Free',
        'price' => 0,
        'duration' => 'unlimited',
        'features' => ['search', 'play', 'limited_playlists'],
        'ads_enabled' => true,
        'upload_limit' => 0
    ],
    'premium_monthly' => [
        'name' => 'Premium Monthly',
        'price' => 9.99,
        'currency' => 'USD',
        'duration' => '1month',
        'features' => ['unlimited_search', 'unlimited_play', 'unlimited_playlists', 'download', 'high_quality'],
        'ads_enabled' => false,
        'upload_limit' => 1000
    ],
    'premium_yearly' => [
        'name' => 'Premium Yearly',
        'price' => 99.99,
        'currency' => 'USD',
        'duration' => '1year',
        'features' => ['unlimited_search', 'unlimited_play', 'unlimited_playlists', 'download', 'high_quality'],
        'ads_enabled' => false,
        'upload_limit' => 1000,
        'discount' => 17 // 17% discount
    ]
];
```

#### Payment Gateway Configuration
```php
// Payment Settings
- payment_gateway: "stripe" // stripe, paypal, razorpay
- currency: "USD"
- supported_currencies: ["USD", "EUR", "GBP", "INR"]
- tax_enabled: true
- tax_rate: 0.18 // 18% tax
- enable_auto_renewal: true
- grace_period_days: 7
- refund_policy_days: 30
```

### 6. Storage & CDN Configuration

#### File Storage
```php
// Storage Settings
- storage_driver: "local" // local, s3, gcs, azure
- cdn_enabled: true
- cdn_provider: "cloudflare"
- max_storage_per_user: "10GB"
- backup_enabled: true
- backup_frequency: "daily"
- retention_period: "30days"

// Image Processing
- image_quality: 85
- thumbnail_sizes: ["150x150", "300x300", "500x500"]
- auto_optimize_images: true
```

### 7. Analytics & Reporting Configuration

#### Analytics Settings
```php
// Analytics Configuration
- enable_user_analytics: true
- enable_content_analytics: true
- enable_revenue_analytics: true
- realtime_analytics_enabled: true
- analytics_retention_period: "2years"

// Report Generation
- daily_reports_enabled: true
- weekly_reports_enabled: true
- monthly_reports_enabled: true
- report_recipients: ["admin@music.hitune.in"]
```

### 8. Security Configuration

#### Security Settings
```php
// Security Configuration
- api_rate_limit: 1000 // requests per hour
- enable_captcha: true
- max_login_attempts: 5
- lockout_duration: 900 // 15 minutes
- password_min_length: 8
- password_complexity_required: true
- two_factor_auth_enabled: false
- session_timeout: 3600 // 1 hour
- ip_whitelist: [] // Empty = all IPs allowed
- country_restrictions: [] // Empty = all countries allowed
```

#### API Security
```php
// API Security Settings
- api_signing_required: true
- request_timeout: 30 // seconds
- max_request_size: "10MB"
- enable_request_logging: true
- suspicious_activity_threshold: 10
- auto_block_suspicious_ips: true
```

### 9. Notification Configuration

#### Email Settings
```php
// Email Configuration
- smtp_host: "smtp.gmail.com"
- smtp_port: 587
- smtp_encryption: "tls"
- from_email: "noreply@music.hitune.in"
- from_name: "Music Hitune"
- enable_email_notifications: true

// Email Templates
- welcome_email_template: "welcome_template"
- verification_email_template: "verification_template"
- password_reset_template: "password_reset_template"
- subscription_confirmation_template: "subscription_template"
```

#### Push Notifications
```php
// Push Notification Settings
- push_provider: "firebase"
- fcm_server_key: "your_fcm_key"
- enable_push_notifications: true
- notification_sound: "default"
- notification_icon: "notification_icon"
```

### 10. Flutter App Admin Controls

#### App Configuration Management
```dart
// Admin can control these Flutter app settings
class AdminControlledConfig {
  // UI Theme
  static Color primaryColor = Color(0xFF2196F3); // Admin configurable
  static Color secondaryColor = Color(0xFF03DAC6); // Admin configurable
  static String fontFamily = 'Roboto'; // Admin configurable
  
  // Features
  static bool enableDarkMode = true; // Admin configurable
  static bool enableOfflineMode = true; // Admin configurable
  static bool enableLyrics = true; // Admin configurable
  static bool enableEqualizer = true; // Admin configurable
  static bool enableSleepTimer = true; // Admin configurable
  
  // Performance
  static int cacheSize = 100; // MB - Admin configurable
  static int preloadCount = 3; // Admin configurable
  static bool enableDataSaver = false; // Admin configurable
  
  // Social Features
  static bool enableSharing = true; // Admin configurable
  static bool enableComments = true; // Admin configurable
  static bool enableRatings = true; // Admin configurable
  static bool enablePlaylists = true; // Admin configurable
}
```

## Admin Panel API Endpoints

### Configuration Management
```
POST /be/client_config          - Get client configuration
POST /be/client_config_update   - Update client configuration
POST /be/user_groups           - Get user groups
POST /be/user_groups_update    - Update user groups
POST /be/subscription_plans    - Get subscription plans
POST /be/subscription_update   - Update subscription plans
```

### Analytics & Reports
```
POST /be/dashboard_highlights  - Get dashboard highlights
POST /be/stats                 - Get statistics
POST /be/user_analytics        - Get user analytics
POST /be/content_analytics     - Get content analytics
POST /be/revenue_analytics     - Get revenue analytics
POST /be/generate_report       - Generate reports
```

### User Management
```
POST /be/user_list            - List users
POST /be/user_edit            - Edit user
POST /be/user_delete          - Delete user
POST /be/user_ban             - Ban user
POST /be/user_unban           - Unban user
POST /be/user_roles           - Manage user roles
```

### Content Management
```
POST /be/content_moderation    - Content moderation
POST /be/upload_settings     - Upload settings
POST /be/content_analytics   - Content analytics
POST /be/copyright_reports   - Copyright reports
```

## Flutter Admin App Configuration

### Admin App Features
```dart
// Admin app can control these settings
class AdminAppFeatures {
  // Dashboard
  static bool enableRealtimeStats = true;
  static bool enableUserManagement = true;
  static bool enableContentManagement = true;
  static bool enableRevenueTracking = true;
  
  // Configuration
  static bool enableAppSettings = true;
  static bool enableUserSettings = true;
  static bool enableContentSettings = true;
  static bool enablePaymentSettings = true;
  
  // Analytics
  static bool enableCustomReports = true;
  static bool enableDataExport = true;
  static bool enableRealtimeAlerts = true;
  static bool enablePerformanceMetrics = true;
}
```

## Configuration Best Practices

### 1. Default Configuration Values
```php
// Recommended default settings
$defaultConfig = [
    'app_name' => 'Music Hitune',
    'enable_search' => true,
    'enable_playlists' => true,
    'enable_social_login' => true,
    'enable_uploads' => true,
    'max_upload_size' => '100MB',
    'audio_quality' => '192kbps',
    'theme_primary_color' => '#2196F3',
    'api_rate_limit' => 1000,
    'enable_analytics' => true,
    'backup_enabled' => true,
    'security_level' => 'medium'
];
```

### 2. Environment-Specific Settings
```php
// Development vs Production settings
if (production) {
    $config['debug'] = false;
    $config['cache_enabled'] = true;
    $config['error_reporting'] = 'minimal';
    $config['analytics_enabled'] = true;
} else {
    $config['debug'] = true;
    $config['cache_enabled'] = false;
    $config['error_reporting'] = 'detailed';
    $config['analytics_enabled'] = false;
}
```

### 3. Security Considerations
```php
// Security best practices
- Never expose sensitive configuration in API responses
- Use environment variables for sensitive data
- Implement configuration validation
- Log configuration changes
- Use secure transmission for sensitive settings
- Implement access control for configuration changes
```

## Flutter Integration for Admin Panel

### Admin Configuration Widget
```dart
// Flutter widget for admin configuration
class AdminConfigWidget extends StatefulWidget {
  @override
  _AdminConfigWidgetState createState() => _AdminConfigWidgetState();
}

class _AdminConfigWidgetState extends State<AdminConfigWidget> {
  Map<String, dynamic> config = {};
  bool isLoading = true;
  
  @override
  void initState() {
    super.initState();
    loadConfiguration();
  }
  
  Future<void> loadConfiguration() async {
    try {
      var response = await ApiService.makeRequest('be/client_config', {}, 
        (json) => json['message']);
      setState(() {
        config = response;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
    }
  }
  
  Future<void> updateConfiguration(String key, dynamic value) async {
    try {
      await ApiService.makeRequest('be/client_config_update', {
        'key': key,
        'value': value.toString()
      }, (json) => json);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Configuration updated successfully'))
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update configuration'))
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Center(child: CircularProgressIndicator());
    }
    
    return ListView(
      children: [
        SwitchListTile(
          title: Text('Enable Search'),
          value: config['enable_search'] ?? true,
          onChanged: (value) => updateConfiguration('enable_search', value),
        ),
        SwitchListTile(
          title: Text('Enable Playlists'),
          value: config['enable_playlists'] ?? true,
          onChanged: (value) => updateConfiguration('enable_playlists', value),
        ),
        SwitchListTile(
          title: Text('Enable Social Login'),
          value: config['enable_social_login'] ?? true,
          onChanged: (value) => updateConfiguration('enable_social_login', value),
        ),
        // Add more configuration options...
      ],
    );
  }
}
```

## Configuration Validation

### Input Validation Rules
```php
// Validation rules for configuration
$validationRules = [
    'app_name' => 'required|string|max:50',
    'max_upload_size' => 'required|string|regex:/^\d+(MB|GB)$/',
    'api_rate_limit' => 'required|integer|min:100|max:10000',
    'theme_primary_color' => 'required|string|regex:/^#[0-9A-F]{6}$/i',
    'currency' => 'required|string|size:3',
    'tax_rate' => 'required|numeric|min:0|max:1',
    'password_min_length' => 'required|integer|min:6|max:20',
    'session_timeout' => 'required|integer|min:300|max:86400'
];
```

## Deployment Checklist

### Configuration Deployment
- [ ] Set production sign keys
- [ ] Configure payment gateways
- [ ] Set up CDN configuration
- [ ] Configure email settings
- [ ] Set up backup schedule
- [ ] Configure security settings
- [ ] Set up analytics tracking
- [ ] Configure notification settings
- [ ] Test all configurations
- [ ] Document all changes

### Flutter App Configuration
- [ ] Set app-specific configurations
- [ ] Configure feature flags
- [ ] Set up push notifications
- [ ] Configure offline caching
- [ ] Set up error reporting
- [ ] Configure performance monitoring
- [ ] Test configuration changes
- [ ] Document app-specific settings

## Support & Maintenance

### Configuration Updates
- Regular review of configuration settings
- Monitor performance impact of changes
- Keep security settings updated
- Backup configuration before changes
- Test configurations in staging environment

### Monitoring & Alerts
- Monitor configuration changes
- Alert on security configuration changes
- Track performance metrics
- Monitor user feedback on settings
- Regular configuration audits

---

**Note**: This configuration guide provides complete control over all admin panel settings. Always test configuration changes in a staging environment before applying to production.