import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_result.dart';
import '../../core/network/api_service.dart';
import '../auth/auth_gate.dart';
import '../config/client_config_service.dart';
import '../subscription/subscription_service.dart';
import 'user_edit_service.dart';

class UpgradePlansScreen extends StatefulWidget {
  const UpgradePlansScreen({super.key});

  @override
  State<UpgradePlansScreen> createState() => _UpgradePlansScreenState();
}

class _UpgradePlansScreenState extends State<UpgradePlansScreen> with WidgetsBindingObserver {
  bool _loading = true;
  String? _error;
  List<dynamic> _plans = [];
  String? _currentPlanId;
  String? _currentPlanName;
  bool _isPremium = false;
  bool _apiSuccess = false;
  bool _isOpeningPayment = false;
  bool _needsRefresh = false;

  /// `plan_features` map from client_config: plan key -> enabled feature keys.
  Map<String, Set<String>> _planFeatures = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPlans();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh plans when user returns from browser (payment)
    if (state == AppLifecycleState.resumed && _needsRefresh) {
      debugPrint('[UPGRADE_PLANS] App resumed, refreshing plans...');
      _needsRefresh = false;
      _loadPlans();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Checking for subscription updates...'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _loadPlans() async {
    setState(() {
      _loading = true;
      _error = null;
      _apiSuccess = false;
    });

    try {
      final ok = await AuthGate.ensureLoggedIn(context, reason: 'Login required to view plans.');
      if (!mounted) return;
      if (!ok) {
        // Auth sheet dismissed or login failed — show a retryable state
        // instead of spinning forever.
        setState(() {
          _loading = false;
          _error = 'Login required to view subscription plans.';
        });
        return;
      }

      // Direct API call to fetch plans from backend
      final api = ApiService.instance;
      final result = await api.postPayloadRaw(endpoint: 'user_subs')
          .timeout(const Duration(seconds: 25), onTimeout: () =>
              ApiResult.failure(const ApiError(code: 'timeout', message: 'Request timed out. Please try again.')));

    if (!mounted) return;

    if (!result.isSuccess || result.data == null) {
      // API failed - backend is down or not accessible
      setState(() {
        _error = result.error?.message ?? 'Failed to connect to server. Please check your internet connection and try again.';
        _loading = false;
        _apiSuccess = false;
      });
      return;
    }

    // API success - parse the plans
    _apiSuccess = true;
    final data = result.data!;
    
    // Check for API error messages
    final messages = data['messages'];
    if (messages is List && messages.isNotEmpty) {
      // Check if API returned 403 (access denied)
      if (messages.any((m) => m.toString() == '403')) {
        setState(() {
          _error = 'Access denied. Please log in again to view subscription plans.';
          _loading = false;
          _apiSuccess = false;
        });
        return;
      }
      
      // Check if API returned an error
      final firstMsg = messages.first;
      if (firstMsg is Map && firstMsg['error'] != null) {
        setState(() {
          _error = firstMsg['error'].toString();
          _loading = false;
        });
        return;
      }
    }

    // Extract plans from response
    // Backend returns plans directly in data['plans'] (not nested in data['data'])
    final plansData = data['plans'];
    if (plansData is Map) {
      // Plans is a map with hash as key (from PHP: $new_items[ $item["hash"] ] = $item)
      _plans = plansData.values.toList();
      debugPrint('[UPGRADE_PLANS] Found ${_plans.length} plans from API');
    } else if (plansData is List) {
      _plans = plansData;
      debugPrint('[UPGRADE_PLANS] Found ${_plans.length} plans from API (list format)');
    } else {
      _plans = [];
      debugPrint('[UPGRADE_PLANS] No plans found in API response. Data keys: ${data.keys}');
    }

      // Get current user's plan from config
      final config = ClientConfigService().config;
      if (config != null) {
        final user = config['user'];
        if (user is Map) {
          // Backend sends user.plan as a plain string ("free", plan name, ...)
          // and user.plan_id as the plan hash when subscribed.
          final rawPlanId = user['plan_id'];
          if (rawPlanId != null && rawPlanId.toString().isNotEmpty) {
            _currentPlanId = rawPlanId.toString();
          }
          final rawPlan = user['plan'] ?? user['subscription'] ?? user['membership'];
          if (rawPlan is Map) {
            _currentPlanName = (rawPlan['name'] ?? rawPlan['title'])?.toString();
            _currentPlanId ??= (rawPlan['hash'] ?? rawPlan['id'])?.toString();
          } else if (rawPlan != null) {
            _currentPlanName = rawPlan.toString();
          }
          final prem = user['is_premium'];
          _isPremium = prem == true || prem == 1 || prem == '1';
          debugPrint('[UPGRADE_PLANS] Current plan: id=$_currentPlanId name=$_currentPlanName premium=$_isPremium');
        }
        _loadPlanFeatureMap(config);
      }

      setState(() => _loading = false);
    } catch (e) {
      debugPrint('[UPGRADE_PLANS] _loadPlans error: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Something went wrong. Please try again.';
          _apiSuccess = false;
        });
      }
    }
  }

  Future<void> _openPayment(String planId, String? url, String period) async {
    setState(() => _isOpeningPayment = true);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Initializing payment...'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 2),
        ),
      );
    }
    
    debugPrint('[UPGRADE_PLANS] Opening payment for plan: $planId, period: $period, url: $url');
    
    String paymentUrl;
    
    if (url != null && url.isNotEmpty) {
      // Use provided URL directly
      paymentUrl = url;
    } else {
      // Call API to get payment link
      paymentUrl = await _getPaymentLinkFromApi(planId, period);
    }
    
    if (paymentUrl.isEmpty) {
      setState(() => _isOpeningPayment = false);
      return;
    }
    
    debugPrint('[UPGRADE_PLANS] Payment URL: $paymentUrl');
    
    final uri = Uri.parse(paymentUrl);
    
    try {
      final canLaunch = await canLaunchUrl(uri);
      debugPrint('[UPGRADE_PLANS] canLaunchUrl: $canLaunch');
      
      if (canLaunch) {
        final result = await launchUrl(
          uri, 
          mode: LaunchMode.inAppWebView, // Open in app instead of external browser
          webViewConfiguration: const WebViewConfiguration(
            enableJavaScript: true,
            enableDomStorage: true,
          ),
        );
        debugPrint('[UPGRADE_PLANS] launchUrl result: $result');
        
        if (result && mounted) {
          _needsRefresh = true; // Mark for refresh when user returns
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Complete payment in the app. Please wait...'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 5),
            ),
          );
        }
      } else {
        debugPrint('[UPGRADE_PLANS] Cannot launch URL: $paymentUrl');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Cannot open payment page. Please try again.'),
              backgroundColor: Colors.red.shade700,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[UPGRADE_PLANS] Error launching URL: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening payment: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isOpeningPayment = false);
      }
    }
  }
  
  Future<String> _getPaymentLinkFromApi(String planId, String period) async {
    try {
      debugPrint('[UPGRADE_PLANS] Calling API: purchase_subs_plan with hash=$planId, period=$period');
      
      // Use ApiService for proper auth headers
      final result = await ApiService.instance.postRaw(
        endpoint: 'purchase_subs_plan',
        data: {
          'hash': planId,
          'period': period,
        },
      );
      
      if (!result.isSuccess || result.data == null) {
        debugPrint('[UPGRADE_PLANS] API call failed: ${result.error?.message}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Payment failed: ${result.error?.message ?? "Unknown error"}'),
              backgroundColor: Colors.red.shade700,
            ),
          );
        }
        return '';
      }
      
      final data = result.data!;
      debugPrint('[UPGRADE_PLANS] API response: $data');

      // Check if API returned success with link — preferred hook first,
      // then a broad scan (backend builds differ in where they put it).
      final messages = data['messages'];
      if (messages is List) {
        for (final msg in messages) {
          if (msg is Map && msg['hook'] == 'subscribe_link' && msg['link'] != null) {
            final link = msg['link'].toString();
            debugPrint('[UPGRADE_PLANS] Got payment link: $link');
            return link;
          }
        }
      }

      final anyLink = UserEditService.extractPaymentUrl(data);
      if (anyLink != null && anyLink.isNotEmpty) {
        debugPrint('[UPGRADE_PLANS] Got payment link (broad scan): $anyLink');
        return anyLink;
      }
      
      // Check for errors in messages
      if (messages is List && messages.isNotEmpty) {
        final firstMsg = messages.first;
        if (firstMsg.toString() == '403') {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Payment failed: Access denied. Please login again.'),
                backgroundColor: Colors.red.shade700,
              ),
            );
          }
          return '';
        }
        if (firstMsg is Map && firstMsg['error'] != null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Payment failed: ${firstMsg['error']}'),
                backgroundColor: Colors.red.shade700,
              ),
            );
          }
          return '';
        }
      }
      
      if (data['error'] != null) {
        final errorMsg = data['error'].toString();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Payment failed: $errorMsg'),
              backgroundColor: Colors.red.shade700,
            ),
          );
        }
        return '';
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Payment failed: No payment link received'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
      return '';
      
    } catch (e) {
      debugPrint('[UPGRADE_PLANS] Error calling payment API: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment initialization failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Upgrade Plans'),
        backgroundColor: Colors.black,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorView()
              : _buildPlansList(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.redAccent.withValues(alpha: 0.8)),
          const SizedBox(height: 16),
          Text(_error!, style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
          const SizedBox(height: 20),
          OutlinedButton(onPressed: _loadPlans, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildPlansList() {
    // Only show default plans if API succeeded but returned no plans
    // Don't show fake plans when backend is down or error occurred
    if (_plans.isEmpty && _apiSuccess) {
      return _buildNoPlansView();
    }

    if (_plans.isEmpty) {
      // This shouldn't happen as we handle empty API response above,
      // but keeping as safety fallback
      return _buildNoPlansView();
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _plans.length,
      itemBuilder: (ctx, i) => _buildPlanCard(_plans[i]),
    );
  }

  Widget _buildNoPlansView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline, size: 64, color: Colors.white.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(
            'No subscription plans available',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please check back later or contact support.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: _loadPlans,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  // Removed - no longer showing fake default plans when backend is down
  // Only show plans that come from the actual backend API

  /// Parses `plan_features` from client_config into a normalized
  /// plan-key -> feature-keys map (accepts both list and map formats).
  void _loadPlanFeatureMap(Map<String, dynamic> config) {
    _planFeatures = {};
    final raw = config['plan_features'] ??
        (config['setting'] is Map ? (config['setting'] as Map)['plan_features'] : null);
    if (raw is! Map) return;
    for (final entry in raw.entries) {
      final value = entry.value;
      final keys = <String>{};
      if (value is List) {
        keys.addAll(value.map((e) => e.toString()));
      } else if (value is Map) {
        for (final f in value.entries) {
          final v = f.value;
          if (v == true || v == 1 || v == '1' || v == 'true') {
            keys.add(f.key.toString());
          }
        }
      }
      if (keys.isNotEmpty) _planFeatures[entry.key.toString()] = keys;
    }
  }

  /// Resolves which `plan_features` entry applies to a plan card.
  /// Matches by hash / slug / name ("HiTune Premium" -> "premium").
  /// Paid plans with no own entry inherit the base "premium" tier.
  Set<String>? _featuresForPlan(Map plan) {
    if (_planFeatures.isEmpty) return null;
    final name = plan['name']?.toString() ?? '';
    final slug = plan['slug']?.toString() ?? '';
    final hash = plan['hash']?.toString() ?? '';
    final norm = name.toLowerCase();
    for (final e in _planFeatures.entries) {
      final k = e.key.toLowerCase();
      if (e.key == hash || k == norm || k == slug.toLowerCase()) return e.value;
    }
    final tokens = norm.split(RegExp(r'[^a-z0-9]+')).where((t) => t.isNotEmpty).toSet();
    for (final e in _planFeatures.entries) {
      final k = e.key.toLowerCase();
      if (tokens.contains(k) || norm.contains(k)) return e.value;
    }
    if (tokens.contains('free') || norm.contains('free')) {
      return _planFeatures['free'];
    }
    return _planFeatures['premium'] ?? _planFeatures['paid'] ?? _planFeatures['default'];
  }

  String _featureLabel(String key) => AppFeatures.labels[key] ?? _prettyFeatureKey(key);

  String _prettyFeatureKey(String key) => key
      .split(RegExp(r'[_\-\s]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  Widget _featureRow(String text, {required bool included}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(
            included ? Icons.check_circle : Icons.remove_circle_outline,
            color: included ? Colors.blueAccent : Colors.white.withValues(alpha: 0.25),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: included ? 0.85 : 0.35),
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(Map plan) {
    final name = plan['name']?.toString() ?? 'Plan';
    final planId = plan['hash']?.toString() ?? '';
    final period = plan['period_first']?.toString() ?? 'monthly';
    final prices = plan['prices'] as Map<String, dynamic>?;
    final finalPrices = prices?['final'] as Map<String, dynamic>?;
    
    // Price can be int or String from backend (e.g. "425.000")
    final rawPrice = finalPrices?[period] ?? prices?['min'] ?? 0;
    final parsedPrice = num.tryParse(rawPrice.toString());
    final priceStr = parsedPrice != null
        ? (parsedPrice == parsedPrice.truncateToDouble()
            ? parsedPrice.toStringAsFixed(0)
            : parsedPrice.toStringAsFixed(2))
        : rawPrice.toString();

    final comment = plan['comment']?.toString() ?? '';

    // Resolve what this plan actually includes. Priority:
    // 1) plan_features map from client_config (same source as feature gating)
    // 2) explicit `features` list on the plan object
    // 3) legacy: plan `comment` split into lines
    final featureKeys = _featuresForPlan(plan);
    final rawFeatures = plan['features'];
    final included = <String>[];
    final excluded = <String>[];
    var showCommentAsDescription = false;

    if (featureKeys != null && featureKeys.isNotEmpty) {
      final union = _planFeatures.values.fold(<String>{}, (a, b) => a..addAll(b));
      final orderedIncluded = [
        ...AppFeatures.all.where(featureKeys.contains),
        ...featureKeys.where((k) => !AppFeatures.all.contains(k)),
      ];
      included.addAll(orderedIncluded.map(_featureLabel));
      final missing = union.difference(featureKeys);
      excluded.addAll([
        ...AppFeatures.all.where(missing.contains),
        ...missing.where((k) => !AppFeatures.all.contains(k)),
      ].map(_featureLabel));
      showCommentAsDescription = comment.isNotEmpty;
    } else if (rawFeatures is List) {
      included.addAll(rawFeatures
          .map((f) => f is Map ? (f['text'] ?? f['name'] ?? '').toString() : f.toString())
          .where((s) => s.isNotEmpty));
      showCommentAsDescription = comment.isNotEmpty;
    } else if (comment.isNotEmpty) {
      included.addAll(comment.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty));
    }

    final discount = plan['discount'];
    final isPopular = discount != null && discount.toString().isNotEmpty && discount.toString() != '0';
    final planNameNorm = _currentPlanName?.toLowerCase();
    final isCurrent = (_currentPlanId != null && _currentPlanId == planId) ||
        (_isPremium &&
            planNameNorm != null &&
            planNameNorm.isNotEmpty &&
            planNameNorm != 'free' &&
            planNameNorm == name.toLowerCase());

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isCurrent ? Colors.blue.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPopular ? Colors.blueAccent : Colors.white.withValues(alpha: 0.1),
          width: isPopular ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isPopular)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: const BoxDecoration(
                color: Colors.blueAccent,
                borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: const Text(
                'MOST POPULAR',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (isCurrent)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'CURRENT',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '\$$priceStr',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '/$period',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 16),
                    ),
                  ],
                ),
                if (showCommentAsDescription) ...[
                  const SizedBox(height: 12),
                  Text(
                    comment,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ],
                if (included.isNotEmpty || excluded.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    "WHAT'S INCLUDED",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final f in included) _featureRow(f, included: true),
                  for (final f in excluded) _featureRow(f, included: false),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: isCurrent || _isOpeningPayment 
                        ? null 
                        : () => _openPayment(planId, plan['url']?.toString(), period),
                    style: FilledButton.styleFrom(
                      backgroundColor: isPopular ? Colors.blueAccent : Colors.white.withValues(alpha: 0.1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isOpeningPayment
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(isCurrent ? 'Current Plan' : 'Upgrade'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
