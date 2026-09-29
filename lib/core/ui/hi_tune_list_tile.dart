import 'package:flutter/material.dart';

import 'cover_image.dart';

/// Apple Music style list tile for tracks.
class HiTuneListTile extends StatelessWidget {
  final String? imageUrl;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  const HiTuneListTile({
    super.key,
    this.imageUrl,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 56,
          height: 56,
          child: _buildImage(theme),
        ),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w500,
          letterSpacing: -0.2,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            )
          : null,
      trailing: trailing,
      onTap: onTap,
    );
  }

  String? _normalizeImageUrl(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    var u = url.trim().replaceAll('\\/', '/');

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
    return CoverImage(
      imageUrl: url,
      lookupTitle: title,
      lookupSubtitle: subtitle,
      placeholder: Container(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Icon(Icons.music_note, color: theme.iconTheme.color?.withValues(alpha: 0.25), size: 24),
      ),
    );
  }
}
