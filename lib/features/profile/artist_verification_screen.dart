import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import '../auth/auth_gate.dart';
import '../../core/network/api_service.dart';

class ArtistVerificationScreen extends StatefulWidget {
  const ArtistVerificationScreen({super.key});

  static Future<void> openWithAuth(BuildContext context) async {
    final ok = await AuthGate.ensureLoggedIn(
      context,
      reason: 'Login required to request artist verification.',
    );
    if (!ok) return;
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ArtistVerificationScreen()),
    );
  }

  @override
  State<ArtistVerificationScreen> createState() => _ArtistVerificationScreenState();
}

class _ArtistVerificationScreenState extends State<ArtistVerificationScreen> {
  final _realName = TextEditingController();
  final _stageName = TextEditingController();
  final _extra = TextEditingController();

  final _api = ApiService.instance;

  bool _loading = false;
  String? _status;
  File? _doc;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final ok = await AuthGate.isLoggedIn();
    if (!ok) return;
    
    try {
      final res = await _api.postRaw(
        endpoint: 'user_verify?tab=m_artist',
        data: {},
      );
      debugPrint('[ARTIST_VERIFY] Load status response: isSuccess=${res.isSuccess}, data=${res.data}');
      
      if (!mounted) return;
      if (res.isSuccess && res.data != null) {
        final data = res.data!;
        // Check for verification status in response
        final status = data['status']?.toString() ?? data['verified']?.toString();
        if (status != null && status.isNotEmpty) {
          setState(() => _status = status);
        }
      }
    } catch (e) {
      debugPrint('[ARTIST_VERIFY] Error loading status: $e');
    }
  }

  @override
  void dispose() {
    _realName.dispose();
    _stageName.dispose();
    _extra.dispose();
    super.dispose();
  }

  // Helper to check for 403 in response messages (backend sends 403 as message, not HTTP status)
  bool _has403InMessages(Map<String, dynamic>? data) {
    if (data == null) return false;
    final messages = data['messages'];
    if (messages is List) {
      for (final msg in messages) {
        if (msg.toString() == '403') {
          return true;
        }
      }
    }
    return false;
  }

  Future<void> _pickDoc() async {
    final ok = await AuthGate.ensureLoggedIn(context, reason: 'Login required to upload document.');
    if (!ok) return;
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: false,
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'pdf'],
    );
    if (!mounted) return;
    if (res == null || res.files.isEmpty) return;
    final p = res.files.single.path;
    if (p == null || p.trim().isEmpty) return;
    setState(() {
      _doc = File(p);
    });
  }

  Future<void> _submit() async {
    final ok = await AuthGate.ensureLoggedIn(context, reason: 'Login required to submit verification.');
    if (!ok) return;

    final rn = _realName.text.trim();
    final sn = _stageName.text.trim();

    if (rn.isEmpty || sn.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Real name and Stage name are required')));
      return;
    }

    if (_doc == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please attach an ID proof document')));
      return;
    }

    setState(() => _loading = true);

    try {
      final file = _doc!;
      final mp = await http.MultipartFile.fromPath('document', file.path);

      final endpoint = 'user_verify?tab=m_artist&action=submit';
      debugPrint('[ARTIST_VERIFY] Submitting to endpoint: $endpoint');
      debugPrint('[ARTIST_VERIFY] Fields: real_name=$rn, stage_name=$sn');
      
      final res = await _api.postMultipart(
        endpoint: endpoint,
        fields: {
          'real_name': rn,
          'stage_name': sn,
          'ad': _extra.text.trim(),
        },
        files: [mp],
      );
      debugPrint('[ARTIST_VERIFY] Response: isSuccess=${res.isSuccess}, error=${res.error?.message}, data=${res.data}');
      
      // Check for 403 in messages (backend sends 403 as message, not HTTP status)
      if (_has403InMessages(res.data)) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session expired. Please login again.')),
        );
        // Optionally redirect to login
        await AuthGate.ensureLoggedIn(context, reason: 'Login required to submit verification.');
        return;
      }
      
      if (!mounted) return;
      if (!res.isSuccess) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.error?.message ?? 'Submit failed')));
        return;
      }

      setState(() {
        _loading = false;
        _status = 'Pending';
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verification request submitted')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Submit failed: $e')));
    }
  }

  InputDecoration _dec(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.08),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AuthGate.isLoggedIn(),
      builder: (context, snap) {
        final loggedIn = snap.data == true;

        return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Artist verification'),
        backgroundColor: Colors.black,
      ),
      body: !loggedIn
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Login required for artist verification', style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => AuthGate.ensureLoggedIn(context, reason: 'Login required to request artist verification.'),
                      child: const Text('Login'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
          if (_status != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified_user_outlined, color: Colors.white.withValues(alpha: 0.85)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Status: $_status',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          if (_status != null) const SizedBox(height: 16),
          TextField(
            controller: _realName,
            style: const TextStyle(color: Colors.white),
            decoration: _dec('Real name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _stageName,
            style: const TextStyle(color: Colors.white),
            decoration: _dec('Stage name'),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _doc == null ? 'Attach document (ID proof)' : 'Selected: ${_doc!.path.split(Platform.pathSeparator).last}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w700),
                  ),
                ),
                OutlinedButton(
                  onPressed: _loading ? null : _pickDoc,
                  child: const Text('Upload'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _extra,
            style: const TextStyle(color: Colors.white),
            maxLines: 4,
            decoration: _dec('Additional data', hint: 'Optional'),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Submit request'),
          ),
          const SizedBox(height: 10),
          Text(
            'After submission, status will show as Pending until verified.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
          ),
              ],
            ),
    );
      },
    );
  }
}
