import 'package:flutter/material.dart';
import 'dart:async';

/// Service to handle deep links and store pending navigation
class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  String? _pendingType;
  String? _pendingSlug;
  bool _hasPendingLink = false;

  final _controller = StreamController<DeepLinkData>.broadcast();
  Stream<DeepLinkData> get onDeepLink => _controller.stream;

  /// Store a pending deep link for later navigation
  void setPendingLink(String type, String slug) {
    _pendingType = type;
    _pendingSlug = slug;
    _hasPendingLink = true;
    debugPrint('[DeepLinkService] Pending link stored: type=$type, slug=$slug');
    
    // Emit the event immediately if anyone is listening
    _controller.add(DeepLinkData(type: type, slug: slug));
  }

  /// Check if there's a pending deep link
  bool get hasPendingLink => _hasPendingLink;

  /// Get and clear the pending deep link
  DeepLinkData? consumePendingLink() {
    if (!_hasPendingLink) return null;
    
    final data = DeepLinkData(type: _pendingType!, slug: _pendingSlug!);
    _pendingType = null;
    _pendingSlug = null;
    _hasPendingLink = false;
    
    debugPrint('[DeepLinkService] Pending link consumed: ${data.type}/${data.slug}');
    return data;
  }

  /// Clear any pending link without consuming
  void clearPendingLink() {
    _pendingType = null;
    _pendingSlug = null;
    _hasPendingLink = false;
  }

  void dispose() {
    _controller.close();
  }
}

/// Data class for deep link information
class DeepLinkData {
  final String type;
  final String slug;

  DeepLinkData({required this.type, required this.slug});

  @override
  String toString() => 'DeepLinkData(type: $type, slug: $slug)';
}
