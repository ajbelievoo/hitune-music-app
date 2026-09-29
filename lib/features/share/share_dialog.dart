import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../player/models/track.dart';
import 'share_service.dart';

class ShareEmbedDialog extends StatefulWidget {
  final Track track;
  final String objectType;
  final String objectHash;
  final String? slug;

  const ShareEmbedDialog({
    super.key,
    required this.track,
    required this.objectType,
    required this.objectHash,
    this.slug,
  });

  @override
  State<ShareEmbedDialog> createState() => _ShareEmbedDialogState();
}

class _ShareEmbedDialogState extends State<ShareEmbedDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  List<String> _embedableUrls = [];
  String? _error;

  // Embed options
  bool _darkMode = true;
  String _accentColor = '1DB954'; // Spotify green default

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadShareData();
  }

  Future<void> _loadShareData() async {
    try {
      final result = await ShareService.instance.fetchShareData(
        objectType: widget.objectType,
        objectHash: widget.objectHash,
      );

      if (result.isSuccess && result.data != null) {
        final data = result.data!;
        final message = data['message'] is Map ? data['message'] as Map<String, dynamic> : null;
        
        setState(() {
          final embedable = message?['embedable'];
          if (embedable is List) {
            _embedableUrls = embedable.whereType<String>().toList();
          }
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = result.error?.message ?? 'Failed to load share data';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  void _copyToClipboard(String text, String successMessage) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(successMessage),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String get _shareUrl => ShareService.instance.buildShareUrl(
        objectType: widget.objectType,
        objectHash: widget.objectHash,
        slug: widget.slug,
      );

  String get _embedUrl => ShareService.instance.buildEmbedUrl(
        objectType: widget.objectType,
        objectHash: widget.objectHash,
        darkMode: _darkMode,
        accentColor: _accentColor,
      );

  String get _embedCode {
    final width = '100%';
    final height = widget.objectType.contains('video') ? '360' : '160';
    return '<iframe src="$_embedUrl" width="$width" height="$height" frameborder="0" allowfullscreen></iframe>';
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final secondaryTextColor = isDark ? Colors.white70 : Colors.black54;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: textColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header with track info
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 48,
                      height: 48,
                      color: isDark ? Colors.white12 : Colors.black12,
                      child: widget.track.coverUrl != null
                          ? Image.network(
                              widget.track.coverUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.music_note,
                                color: secondaryTextColor,
                              ),
                            )
                          : Icon(Icons.music_note, color: secondaryTextColor),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        if (widget.track.subtitle != null)
                          Text(
                            widget.track.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: secondaryTextColor),
                  ),
                ],
              ),
            ),
            // Tabs
            TabBar(
              controller: _tabController,
              labelColor: isDark ? const Color(0xFF1DB954) : Colors.green.shade700,
              unselectedLabelColor: secondaryTextColor,
              indicatorColor: isDark ? const Color(0xFF1DB954) : Colors.green.shade700,
              tabs: const [
                Tab(text: 'Share'),
                Tab(text: 'Embed'),
              ],
            ),
            // Tab content
            SizedBox(
              height: 320,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildShareTab(textColor, secondaryTextColor),
                  _buildEmbedTab(textColor, secondaryTextColor, isDark),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShareTab(Color textColor, Color secondaryTextColor) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _error!,
            style: TextStyle(color: secondaryTextColor),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Share this track',
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          // Share URL
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: textColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: textColor.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                Icon(Icons.link, size: 18, color: secondaryTextColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _shareUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 13,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _copyToClipboard(_shareUrl, 'Link copied to clipboard'),
                  child: const Text('Copy'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Social Share Buttons - First Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildSocialButton(
                icon: Icons.chat_bubble,
                label: 'WhatsApp',
                color: const Color(0xFF25D366),
                onTap: () => _shareToWhatsApp(),
              ),
              _buildSocialButton(
                icon: Icons.telegram,
                label: 'Telegram',
                color: const Color(0xFF0088cc),
                onTap: () => _shareToTelegram(),
              ),
              _buildSocialButton(
                icon: Icons.facebook,
                label: 'Facebook',
                color: const Color(0xFF1877F2),
                onTap: () => _shareToFacebook(),
              ),
              _buildSocialButton(
                icon: Icons.more_vert,
                label: 'More',
                color: Colors.grey,
                onTap: () => _shareNative(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Copy & General Share - Second Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildShareButton(
                icon: Icons.content_copy,
                label: 'Copy Link',
                onTap: () => _copyToClipboard(_shareUrl, 'Link copied to clipboard'),
              ),
              _buildShareButton(
                icon: Icons.share,
                label: 'Share',
                onTap: () => _shareNative(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmbedTab(Color textColor, Color secondaryTextColor, bool isDark) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _error!,
            style: TextStyle(color: secondaryTextColor),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // Check if embeddable - always enabled now
    // Removed the check to allow embed for all tracks
    /*
    if (_embedableUrls.isEmpty && widget.track.url.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.block,
                size: 48,
                color: secondaryTextColor.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 12),
              Text(
                'Embedding is not available for this track',
                style: TextStyle(color: secondaryTextColor),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    */

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Options
          Row(
            children: [
              Expanded(
                child: _buildOptionChip(
                  label: 'Dark',
                  selected: _darkMode,
                  onTap: () => setState(() => _darkMode = true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildOptionChip(
                  label: 'Light',
                  selected: !_darkMode,
                  onTap: () => setState(() => _darkMode = false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Embed code
          Text(
            'Embed Code',
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1A1A) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: textColor.withValues(alpha: 0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _embedCode,
                  style: TextStyle(
                    color: secondaryTextColor,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _copyToClipboard(_embedCode, 'Embed code copied'),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy Code'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Direct URL
          Text(
            'Direct URL',
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: textColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: textColor.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _embedUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 12,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _copyToClipboard(_embedUrl, 'Embed URL copied'),
                  child: const Text('Copy'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Social sharing methods
  void _shareNative() {
    final text = '${widget.track.title} - ${widget.track.subtitle ?? 'Listen on HiTune'}\n$_shareUrl';
    Share.share(text, subject: widget.track.title);
  }

  Future<void> _shareToWhatsApp() async {
    final text = '${widget.track.title} - ${widget.track.subtitle ?? 'Listen on HiTune'}\n$_shareUrl';
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _copyToClipboard(_shareUrl, 'Link copied - WhatsApp not installed');
    }
  }

  Future<void> _shareToTelegram() async {
    final uri = Uri.parse('https://t.me/share/url?url=${Uri.encodeComponent(_shareUrl)}&text=${Uri.encodeComponent(widget.track.title)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _copyToClipboard(_shareUrl, 'Link copied - Telegram not installed');
    }
  }

  Future<void> _shareToFacebook() async {
    final uri = Uri.parse('https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(_shareUrl)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _copyToClipboard(_shareUrl, 'Link copied - Facebook not available');
    }
  }

  Widget _buildSocialButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: color,
                size: 22,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShareButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? (isDark ? const Color(0xFF1DB954) : Colors.green.shade600)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? (isDark ? const Color(0xFF1DB954) : Colors.green.shade600)
                : Colors.grey.shade600,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.grey.shade400,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

/// Helper function to show the share dialog
void showShareEmbedDialog(BuildContext context, {
  required Track track,
  required String objectType,
  required String objectHash,
  String? slug,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => ShareEmbedDialog(
      track: track,
      objectType: objectType,
      objectHash: objectHash,
      slug: slug,
    ),
  );
}
