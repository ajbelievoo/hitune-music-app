import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../player/mini_player.dart';
import '../player/player_service.dart';

class InfoScreen extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String html;
  final String? bg;

  const InfoScreen({
    super.key,
    required this.title,
    required this.html,
    this.subtitle,
    this.bg,
  });

  String _stripHtml(String input) {
    return input.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String? _extractImageUrl(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final m = RegExp('https?://[^\\s\'\"]+', caseSensitive: false).firstMatch(raw);
    return m?.group(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cleanTitle = title.isEmpty ? 'Info' : title;
    final imageUrl = _extractImageUrl(bg);
    final text = _stripHtml(html);

    return Scaffold(
      backgroundColor: Colors.black,
      bottomNavigationBar: SafeArea(
        top: false,
        child: MiniPlayer(player: PlayerService.instance),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.45),
                    Colors.black,
                  ],
                ),
              ),
            ),
          ),
          if (imageUrl != null)
            Positioned.fill(
              child: Opacity(
                opacity: 0.35,
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => const SizedBox.shrink(),
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: Container(color: Colors.black.withValues(alpha: 0.25)),
            ),
          ),
          SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  leading: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
                  ),
                  title: Text(cleanTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        color: Colors.white.withValues(alpha: 0.06),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        boxShadow: [
                          BoxShadow(
                            blurRadius: 40,
                            spreadRadius: 1,
                            color: Colors.black.withValues(alpha: 0.55),
                            offset: const Offset(0, 18),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cleanTitle,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                          if (subtitle != null && subtitle!.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              subtitle!,
                              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.75)),
                            ),
                          ],
                          const SizedBox(height: 14),
                          Text(
                            text,
                            style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.9), height: 1.35),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 90)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
