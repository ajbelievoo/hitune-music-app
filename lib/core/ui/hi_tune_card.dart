import 'package:flutter/material.dart';

import 'cover_image.dart';

/// Apple Music style album / playlist card.
class HiTuneCard extends StatelessWidget {
  final String? imageUrl;
  final String title;
  final String? subtitle;
  final double width;
  final double height;
  final VoidCallback? onTap;
  final Widget? playOverlay;

  const HiTuneCard({
    super.key,
    this.imageUrl,
    required this.title,
    this.subtitle,
    this.width = 152,
    this.height = 152,
    this.onTap,
    this.playOverlay,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 12,
                      spreadRadius: 0,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildImage(theme),
                    if (playOverlay != null) playOverlay!,
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String? _normalizeImageUrl(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    var u = url.trim().replaceAll('\\/', '/');

    // Convert WebP to JPEG for Android compatibility
    final webpRegex = RegExp(r'\.webp([?#]|$)', caseSensitive: false);
    if (webpRegex.hasMatch(u)) {
      u = u.replaceAll(webpRegex, '.jpg\$1');
    }

    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    if (u.startsWith('//')) return 'https:$u';
    if (u.startsWith('/')) return 'https://music.hitune.in$u';
    return 'https://music.hitune.in/$u';
  }

  Widget _buildImage(ThemeData theme) {
    final url = _normalizeImageUrl(imageUrl);
    final fallback = Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(Icons.music_note, color: theme.iconTheme.color?.withValues(alpha: 0.25), size: 40),
    );

    return CoverImage(
      imageUrl: url,
      lookupTitle: title,
      lookupSubtitle: subtitle,
      placeholder: fallback,
    );
  }
}
