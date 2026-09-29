import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../utils/artwork_lookup.dart';

/// Cover image for cards/rail items.
///
/// Loads [imageUrl] via [CachedNetworkImage] at medium filter quality.
/// When the URL is missing — or fails to load — and [lookupTitle] is
/// provided, falls back to an iTunes artwork lookup so items the backend
/// has no art for (dummy placeholders) still get a real poster.
class CoverImage extends StatefulWidget {
  final String? imageUrl;
  final String? lookupTitle;
  final String? lookupSubtitle;
  final BoxFit fit;
  final Widget placeholder;

  const CoverImage({
    super.key,
    this.imageUrl,
    this.lookupTitle,
    this.lookupSubtitle,
    this.fit = BoxFit.cover,
    this.placeholder = const SizedBox.shrink(),
  });

  @override
  State<CoverImage> createState() => _CoverImageState();
}

class _CoverImageState extends State<CoverImage> {
  bool _lookup = false;

  @override
  void didUpdateWidget(CoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) _lookup = false;
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.imageUrl?.trim();
    if (!_lookup && url != null && url.isNotEmpty) {
      return _net(url, onError: _startLookup);
    }

    final title = widget.lookupTitle?.trim();
    if (title == null || title.isEmpty) return widget.placeholder;

    return FutureBuilder<String?>(
      future: ArtworkLookup.instance.lookup(title, widget.lookupSubtitle),
      builder: (context, snap) {
        final found = snap.data;
        if (found == null || found.isEmpty) return widget.placeholder;
        return _net(found);
      },
    );
  }

  void _startLookup() {
    if (!mounted || _lookup) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _lookup = true);
    });
  }

  Widget _net(String url, {VoidCallback? onError}) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: widget.fit,
      filterQuality: FilterQuality.medium,
      placeholder: (_, __) => widget.placeholder,
      errorWidget: (_, __, ___) {
        onError?.call();
        return widget.placeholder;
      },
    );
  }
}
