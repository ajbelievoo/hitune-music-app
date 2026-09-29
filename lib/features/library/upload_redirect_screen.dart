import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Strategy doc §7: direct song upload inside HiTune Music is disabled —
/// every "Upload" action sends the creator to the HiTune Distribution
/// portal, where uploads, metadata and distribution are handled.
class UploadRedirectScreen extends StatefulWidget {
  const UploadRedirectScreen({super.key});

  static const String distributionUrl = 'https://distribution.hitune.in/';

  @override
  State<UploadRedirectScreen> createState() => _UploadRedirectScreenState();
}

class _UploadRedirectScreenState extends State<UploadRedirectScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPortal());
  }

  Future<void> _openPortal() async {
    final uri = Uri.parse(UploadRedirectScreen.distributionUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Portal open failure is non-fatal — the button below stays available.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          'Upload Music',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: const Color(0xFF1DB954).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.cloud_upload_outlined,
                  color: Color(0xFF1DB954),
                  size: 48,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Uploads moved to HiTune Distribution',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Songs are now uploaded through the HiTune Distribution portal. '
                'There you can add artist details, album art, ISRC codes, AI declarations '
                'and choose platforms — approved releases appear here automatically.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _openPortal,
                  icon: const Icon(Icons.open_in_new, size: 20),
                  label: const Text(
                    'Open HiTune Distribution',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1DB954),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
