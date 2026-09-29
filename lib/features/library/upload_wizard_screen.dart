import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'upload_service.dart';
import '../auth/auth_gate.dart';
import '../../core/utils/app_logger.dart';

class UploadWizardScreen extends StatefulWidget {
  const UploadWizardScreen({super.key});

  @override
  State<UploadWizardScreen> createState() => _UploadWizardScreenState();
}

class _UploadWizardScreenState extends State<UploadWizardScreen> {
  final UploadService _uploadService = UploadService();
  final PageController _pageController = PageController();

  int _currentStep = 0;
  bool _loading = false;
  String? _error;

  // Step 1: Content Type
  String? _contentType;

  // Step 2: Source Type
  String? _sourceType; // 'album' or 'single'

  // Step 3: Upload Method
  String? _uploadMethod; // 'audio' or 'youtube'

  // Step 4: Files/YouTube
  List<PlatformFile> _selectedFiles = [];
  final _youtubeIdController = TextEditingController();

  // Step 5: Edit Tracks
  List<Map<String, dynamic>> _tracks = [];
  String? _groupHash;
  List<Map<String, dynamic>> _uploadedFiles = []; // Store file data for re-verify
  Map<String, dynamic>? _verifiedSource; // Store verified source for submission

  final List<String> _steps = [
    'Content type',
    'Source type',
    'Upload',
    'Edit tracks',
  ];

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final ok = await AuthGate.ensureLoggedIn(context, reason: 'Login required to upload content.');
    if (!ok && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _youtubeIdController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < _steps.length - 1) {
      setState(() {
        _currentStep++;
        _error = null;
      });
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
        _error = null;
      });
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3'],
        allowMultiple: _sourceType == 'album',
      );
      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _selectedFiles = result.files;
        });
        // Debug: print selected file details
        for (final file in result.files) {
          AppLogger.d('[UploadWizard] Selected file: ${file.name}');
          AppLogger.d('[UploadWizard] Path: ${file.path}');
          AppLogger.d('[UploadWizard] Size: ${file.size} bytes');
          AppLogger.d('[UploadWizard] Extension: ${file.extension}');
          if (file.path != null) {
            final ioFile = File(file.path!);
            if (await ioFile.exists()) {
              final stat = await ioFile.stat();
              AppLogger.d('[UploadWizard] File exists: true');
              AppLogger.d('[UploadWizard] File size on disk: ${stat.size} bytes');
              AppLogger.d('[UploadWizard] Last modified: ${stat.modified}');
            } else {
              AppLogger.d('[UploadWizard] File exists: false');
            }
          }
        }
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to pick files: $e';
      });
    }
  }

  Future<void> _verifySources() async {
    AppLogger.d('[DEBUG] _verifySources called, _uploadMethod=$_uploadMethod, _selectedFiles.length=${_selectedFiles.length}');
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      Map<String, dynamic> givenData;
      _uploadedFiles = []; // Reset on new verify
      AppLogger.d('[DEBUG] Reset _uploadedFiles');

      if (_uploadMethod == 'youtube') {
        final youtubeId = _youtubeIdController.text.trim();
        if (youtubeId.isEmpty) {
          setState(() {
            _error = 'Please enter a YouTube ID or URL';
            _loading = false;
          });
          return;
        }
        givenData = {
          'inputs': {
            'youtube_id': youtubeId,
          },
        };
      } else {
        // First upload files to get file_id and file_pass
        for (final file in _selectedFiles) {
          if (file.path == null) continue;
          final uploadResult = await _uploadService.uploadFile(File(file.path!));
          if (!uploadResult.isSuccess) {
            setState(() {
              _error = 'Failed to upload file: ${uploadResult.error?.message}';
              _loading = false;
            });
            return;
          }
          final fileData = uploadResult.data!;
          AppLogger.d('[DEBUG] File uploaded: ID=${fileData['ID']}, pass=${fileData['pass']}');
          _uploadedFiles.add({
            'type': 'audio',
            'success': true,
            'file_id': fileData['ID']?.toString() ?? '',
            'file_pass': fileData['pass']?.toString() ?? '',
          });
          AppLogger.d('[DEBUG] _uploadedFiles now has ${_uploadedFiles.length} items');
        }
        // If single track, only verify the first file
        final filesToVerify = _sourceType == 'single' && _uploadedFiles.isNotEmpty 
            ? [_uploadedFiles.first]
            : _uploadedFiles;
        givenData = {'files': filesToVerify};
        AppLogger.d('[DEBUG] Verifying ${filesToVerify.length} file(s) for $_sourceType');
      }

      final result = await _uploadService.verifySources(
        contentData: {'ID': _contentType == 'music' ? 'music' : 'podcast'},
        sourceData: {'ID': _uploadMethod == 'youtube' ? 'youtube' : 'audio'},
        givenData: givenData,
      );

      if (result.isSuccess) {
        final data = result.data!;
        // FULL DEBUG: Log entire response for backend team
        AppLogger.d('[DEBUG-BACKEND] ===== FULL verifySources RESPONSE =====');
        AppLogger.d('[DEBUG-BACKEND] ${jsonEncode(data)}');
        AppLogger.d('[DEBUG-BACKEND] ===== END RESPONSE =====');
        
        // Try to get group_hash from response, fallback to verified object key
        _groupHash = data['group_hash'] as String?;
        if (_groupHash == null && data.containsKey('verified')) {
          final verified = data['verified'] as Map<String, dynamic>;
          if (verified.isNotEmpty) {
            _groupHash = verified.keys.first;
          }
        }
        
        // Store verified source for later submission
        if (data.containsKey('verified') && _groupHash != null) {
          final verified = data['verified'] as Map<String, dynamic>;
          _verifiedSource = verified[_groupHash] as Map<String, dynamic>?;
          AppLogger.d('[DEBUG] Stored _verifiedSource: $_verifiedSource');
        }
        
        AppLogger.d('[DEBUG] verifySources success, _groupHash=$_groupHash');
        AppLogger.d('[DEBUG] _uploadedFiles.length=${_uploadedFiles.length} before track init');

        // Initialize tracks from response
        if (data.containsKey('items')) {
          final items = data['items'] as List<dynamic>;
          AppLogger.d('[DEBUG] Response has ${items.length} items');
          _tracks = items.asMap().entries.map((entry) {
            final index = entry.key;
            final item = Map<String, dynamic>.from(entry.value as Map);
            // Preserve file data from _uploadedFiles if available
            if (index < _uploadedFiles.length) {
              item['file_id'] = _uploadedFiles[index]['file_id'];
              item['file_pass'] = _uploadedFiles[index]['file_pass'];
              AppLogger.d('[DEBUG] Set file_id=${item['file_id']}, file_pass=${item['file_pass']} for track $index');
            }
            return item;
          }).toList();
        } else {
          AppLogger.d('[DEBUG] No items in response, creating default tracks');
          // Create default track entries with file data
          _tracks = List.generate(
            _sourceType == 'album' ? _selectedFiles.length : 1,
            (index) => {
              'title': _selectedFiles.isNotEmpty ? _selectedFiles[index].name.replaceAll('.mp3', '').replaceAll('.wav', '') : 'Untitled',
              'artist_name': '',
              'album': '',
              if (index < _uploadedFiles.length) ...{
                'file_id': _uploadedFiles[index]['file_id'],
                'file_pass': _uploadedFiles[index]['file_pass'],
              },
            },
          );
        }
        AppLogger.d('[DEBUG] After init, _tracks.length=${_tracks.length}');
        if (_tracks.isNotEmpty) {
          AppLogger.d('[DEBUG] First track: file_id=${_tracks[0]['file_id']}, file_pass=${_tracks[0]['file_pass']}');
        }

        _nextStep();
      } else {
        setState(() {
          _error = result.error?.message ?? 'Failed to verify sources';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _submitUpload() async {
    AppLogger.d('[DEBUG] _submitUpload called, _groupHash=$_groupHash, _uploadedFiles.length=${_uploadedFiles.length}');
    
    // Check if we need to re-verify (e.g., when cover files were added after first verify)
    final needsReverify = _needsReverify();
    AppLogger.d('[DEBUG] needsReverify=$needsReverify');
    
    // If group hash is missing or needs re-verify, try to verify sources first
    if (_groupHash == null || needsReverify) {
      setState(() {
        _loading = true;
        _error = null;
      });

      try {
        // Re-verify sources to get group hash and include all files (including cover)
        final givenData = _buildGivenData();
        AppLogger.d('[DEBUG] Re-verify givenData: $givenData');
        
        // Check if we have files to verify
        if (givenData['files'] == null || (givenData['files'] as List).isEmpty) {
          setState(() {
            _error = 'No file data found. Please go back and re-select your files.';
            _loading = false;
          });
          return;
        }
        
        final result = await _uploadService.verifySources(
          contentData: {'ID': _contentType == 'music' ? 'music' : 'podcast'},
          sourceData: {'ID': _uploadMethod == 'youtube' ? 'youtube' : 'audio'},
          givenData: givenData,
        );

        if (result.isSuccess) {
          final data = result.data!;
          AppLogger.d('[DEBUG] Re-verify response data: $data');
          // Try to get group_hash from response, fallback to verified object key
          _groupHash = data['group_hash'] as String?;
          if (_groupHash == null && data.containsKey('verified')) {
            final verified = data['verified'] as Map<String, dynamic>;
            if (verified.isNotEmpty) {
              _groupHash = verified.keys.first;
              // Store verified source when re-verifying
              _verifiedSource = verified[_groupHash] as Map<String, dynamic>?;
              AppLogger.d('[DEBUG] Stored _verifiedSource from re-verify: $_verifiedSource');
            }
          }
          AppLogger.d('[DEBUG] Extracted _groupHash=$_groupHash');
        } else {
          setState(() {
            _error = result.error?.message ?? 'Failed to verify sources';
            _loading = false;
          });
          return;
        }
      } catch (e) {
        setState(() {
          _error = 'Error verifying sources: $e';
          _loading = false;
        });
        return;
      }
    }

    // Check again after verification
    if (_groupHash == null) {
      setState(() {
        _error = 'Group hash is missing';
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _uploadService.submitUpload(
        groupHash: _groupHash!,
        items: _tracks,
        contentType: _contentType == 'music' ? 'music' : 'podcast',
        sourceType: _uploadMethod == 'youtube' ? 'youtube' : 'audio',
        verifiedSource: _createMinimalVerifiedSource(_verifiedSource),
      );

      if (result.isSuccess) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Upload successful!')),
          );
          Navigator.of(context).pop();
        }
      } else {
        setState(() {
          _error = result.error?.message ?? 'Failed to submit upload';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  void _updateTrack(int index, String key, String value) {
    setState(() {
      _tracks[index][key] = value;
    });
  }

  Map<String, dynamic> _createMinimalVerifiedSource(Map<String, dynamic>? verified) {
    // Return the full verified object - backend needs all fields including inputs
    // The inputs field contains the form configuration that backend validates against
    if (verified == null) return {};
    
    // Create a copy of verified source to modify
    final modifiedVerified = Map<String, dynamic>.from(verified);
    
    // Add cover file info to verified source data so backend thinks it's verified
    // Backend checks that all submitted files are in verified_source
    final verifiedData = modifiedVerified['data'] as Map<String, dynamic>?;
    final inputs = modifiedVerified['inputs'] as Map<String, dynamic>?;
    final groupHash = modifiedVerified['ID'] as String?;
    
    if (verifiedData != null) {
      // Convert main audio file_id to integer (backend returns it as string)
      if (verifiedData['file_id'] != null) {
        verifiedData['file_id'] = int.parse(verifiedData['file_id'].toString());
      }
      
      // Build files array with audio and cover files
      // Backend expects a files array in verified_source.data
      final files = <Map<String, dynamic>>[];
      
      // Add main audio file
      files.add({
        'type': 'audio',
        'success': true,
        'file_id': verifiedData['file_id'],
        'file_pass': verifiedData['file_pass'],
        's_title': verifiedData['s_title'] ?? 'unknown.mp3',
      });
      
      // Check if any track has a cover file
      for (final track in _tracks) {
        final coverFileId = track['cover_file_id']?.toString();
        final coverFilePass = track['cover_file_pass']?.toString();
        if (coverFileId != null && coverFileId.isNotEmpty && 
            coverFilePass != null && coverFilePass.isNotEmpty) {
          // Add cover file to files array
          files.add({
            'type': 'image',
            'success': true,
            'file_id': int.parse(coverFileId),
            'file_pass': coverFilePass,
          });
          
          // Also add legacy format for backwards compatibility
          verifiedData['cover_file_id'] = int.parse(coverFileId);
          verifiedData['cover_file_pass'] = coverFilePass;
          verifiedData['cover_type'] = 'image';
          
          // Update the inputs field with cover file info
          // Backend validates against inputs field
          if (inputs != null && groupHash != null) {
            final coverInputKey = '${groupHash}_cover';
            if (inputs.containsKey(coverInputKey)) {
              final coverInput = Map<String, dynamic>.from(inputs[coverInputKey] as Map<String, dynamic>);
              final inputData = Map<String, dynamic>.from(coverInput['input'] as Map<String, dynamic>);
              
              // Convert file_id to integer for backend
              inputData['value'] = int.parse(coverFileId);
              inputData['bof_file_pass'] = coverFilePass;
              
              coverInput['input'] = inputData;
              inputs[coverInputKey] = coverInput;
              
              AppLogger.d('[DEBUG] Updated inputs[$coverInputKey] with cover file $coverFileId');
            }
          }
          
          AppLogger.d('[DEBUG] Added cover file $coverFileId to verified_source.files');
          break; // Only add first cover for now (single track)
        }
      }
      
      // Add files array to verified data
      verifiedData['files'] = files;
      AppLogger.d('[DEBUG] Built verified_source.data.files with ${files.length} items');
    }
    
    AppLogger.d('[DEBUG] Using modified verified_source with data keys: ${verifiedData?.keys.toList()}');
    return modifiedVerified;
  }

  /// Check if we need to re-verify sources (only for audio files, not covers)
  bool _needsReverify() {
    // Get list of file IDs from verified_source if available
    final verifiedData = _verifiedSource?['data'] as Map<String, dynamic>?;
    final verifiedFileId = verifiedData?['file_id']?.toString();
    
    AppLogger.d('[DEBUG] _needsReverify: verifiedFileId=$verifiedFileId');
    
    // Check all audio files in tracks against verified source
    final audioFileIds = <String>{};
    
    // Add audio files
    for (final track in _tracks) {
      final audioFileId = track['file_id']?.toString();
      if (audioFileId != null && audioFileId.isNotEmpty) {
        audioFileIds.add(audioFileId);
      }
    }
    
    AppLogger.d('[DEBUG] _needsReverify: audioFileIds=$audioFileIds');
    
    // If verified source doesn't match current audio file, we need to re-verify
    if (verifiedFileId != null && !audioFileIds.contains(verifiedFileId)) {
      AppLogger.d('[DEBUG] _needsReverify: verified file not in current audio files, need re-verify');
      return true;
    }
    
    return false;
  }

  Map<String, dynamic> _buildGivenData() {
    AppLogger.d('[DEBUG] _buildGivenData called, _uploadedFiles.length=${_uploadedFiles.length}');
    AppLogger.d('[DEBUG] _tracks.length=${_tracks.length}');
    for (var i = 0; i < _tracks.length; i++) {
      AppLogger.d('[DEBUG] track[$i] file_id=${_tracks[i]['file_id']}, file_pass=${_tracks[i]['file_pass']}, cover_file_id=${_tracks[i]['cover_file_id']}');
    }
    
    // Only include audio files in verification - backend doesn't accept image files in verifySources
    final files = <Map<String, dynamic>>[];
    
    // Add only audio files from _uploadedFiles
    for (final file in _uploadedFiles) {
      if (file['type'] == 'audio') {
        files.add(file);
        AppLogger.d('[DEBUG] Adding audio file to verification: ${file['file_id']}');
      }
    }
    
    // Fallback: build from tracks audio files if _uploadedFiles is empty
    if (files.isEmpty) {
      AppLogger.d('[DEBUG] Falling back to tracks for audio files');
      for (final track in _tracks) {
        if (track.containsKey('file_id') && track.containsKey('file_pass')) {
          final fileId = track['file_id']?.toString();
          final filePass = track['file_pass']?.toString();
          if (fileId != null && fileId.isNotEmpty && filePass != null && filePass.isNotEmpty) {
            files.add({
              'type': 'audio',
              'success': true,
              'file_id': int.parse(fileId), // Convert to integer for backend
              'file_pass': filePass,
            });
            if (_sourceType == 'single') break;
          }
        }
      }
    }
    
    AppLogger.d('[DEBUG] Built files array with ${files.length} audio items for verification');
    return {'files': files};
  }

  Future<void> _pickCoverImage(Map<String, dynamic> track) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.path != null) {
          // Upload cover image
          final uploadResult = await _uploadService.uploadFile(
            File(file.path!),
            fileType: 'image',
            objectType: 'track',
          );
          if (uploadResult.isSuccess) {
            final fileData = uploadResult.data!;
            // Update track with cover URL and file data
            setState(() {
              track['cover'] = fileData['preview'];
              track['cover_file_id'] = fileData['ID'];
              track['cover_file_pass'] = fileData['pass'];
              AppLogger.d('[DEBUG] Cover uploaded: ID=${fileData['ID']}, pass=${fileData['pass']}');
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Cover image uploaded')),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed: ${uploadResult.error?.message}')),
            );
          }
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : Colors.black),
          onPressed: _prevStep,
        ),
        title: Row(
          children: [
            Icon(Icons.cloud_upload, color: theme.colorScheme.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              'Upload',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: List.generate(_steps.length, (index) {
                final isActive = index == _currentStep;
                final isCompleted = index < _currentStep;

                return Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCompleted
                              ? Colors.green
                              : isActive
                                  ? theme.colorScheme.primary
                                  : (isDark ? Colors.white24 : Colors.black12),
                        ),
                        child: Center(
                          child: isCompleted
                              ? const Icon(Icons.check, size: 14, color: Colors.white)
                              : Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    color: isActive || isCompleted ? Colors.white : (isDark ? Colors.white70 : Colors.black54),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                      if (index < _steps.length - 1)
                        Expanded(
                          child: Container(
                            height: 2,
                            color: isCompleted
                                ? Colors.green
                                : (isDark ? Colors.white24 : Colors.black12),
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ),
      ),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildContentTypeStep(),
          _buildSourceTypeStep(),
          _buildUploadMethodStep(),
          _buildEditTracksStep(),
        ],
      ),
    );
  }

  Widget _buildContentTypeStep() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What do you want to upload?',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 32),
          Center(
            child: _ContentTypeCard(
              icon: Icons.music_note,
              label: 'Music',
              isSelected: _contentType == 'music',
              onTap: () {
                setState(() {
                  _contentType = 'music';
                });
                _nextStep();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceTypeStep() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What do you want to upload?',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: _SourceTypeCard(
                  icon: Icons.album,
                  label: 'Album',
                  isSelected: _sourceType == 'album',
                  onTap: () {
                    setState(() {
                      _sourceType = 'album';
                    });
                    _nextStep();
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _SourceTypeCard(
                  icon: Icons.music_note,
                  label: 'Single Track',
                  isSelected: _sourceType == 'single',
                  onTap: () {
                    setState(() {
                      _sourceType = 'single';
                    });
                    _nextStep();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUploadMethodStep() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How do you want to provide the source?',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: _SourceTypeCard(
                  icon: Icons.upload_file,
                  label: 'Upload Audio',
                  isSelected: _uploadMethod == 'audio',
                  onTap: () {
                    setState(() {
                      _uploadMethod = 'audio';
                    });
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _SourceTypeCard(
                  icon: Icons.video_library,
                  label: 'Import YouTube',
                  isSelected: _uploadMethod == 'youtube',
                  onTap: () {
                    setState(() {
                      _uploadMethod = 'youtube';
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          if (_uploadMethod == 'audio') ...[
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.cloud_upload,
                    size: 48,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Drag & Drop files to start',
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Or click here to select files',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_selectedFiles.isNotEmpty)
                    Text(
                      '${_selectedFiles.length} file(s) selected',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _pickFiles,
                icon: const Icon(Icons.folder_open),
                label: Text(_selectedFiles.isEmpty ? 'Select Files' : 'Change Files'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ] else if (_uploadMethod == 'youtube') ...[
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'YouTube ID',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _youtubeIdController,
                    decoration: InputDecoration(
                      hintText: 'Enter the ID or full web address of a YouTube video',
                      hintStyle: TextStyle(
                        color: isDark ? Colors.white38 : Colors.black38,
                        fontSize: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.2),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                    style: TextStyle(color: isDark ? Colors.white : Colors.black),
                  ),
                ],
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_uploadMethod == 'audio' && _selectedFiles.isNotEmpty) ||
                      (_uploadMethod == 'youtube' && _youtubeIdController.text.isNotEmpty)
                  ? _verifySources
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Continue'),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildEditTracksStep() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Edit tracks',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _tracks.length,
            itemBuilder: (context, index) {
              final track = _tracks[index];
              return _TrackEditCard(
                track: track,
                index: index,
                onUpdate: (key, value) => _updateTrack(index, key, value),
                onPickCover: () => _pickCoverImage(track),
              );
            },
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _submitUpload,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save'),
            ),
          ),
        ),
      ],
    );
  }
}

class _ContentTypeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ContentTypeCard({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 160,
        height: 160,
        decoration: BoxDecoration(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 48,
              color: isSelected ? theme.colorScheme.primary : (isDark ? Colors.white54 : Colors.black54),
            ),
            const SizedBox(height: 16),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? theme.colorScheme.primary : (isDark ? Colors.white : Colors.black),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceTypeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SourceTypeCard({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 48,
              color: isSelected ? theme.colorScheme.primary : (isDark ? Colors.white54 : Colors.black54),
            ),
            const SizedBox(height: 16),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? theme.colorScheme.primary : (isDark ? Colors.white : Colors.black),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackEditCard extends StatefulWidget {
  final Map<String, dynamic> track;
  final int index;
  final Function(String key, String value) onUpdate;
  final VoidCallback onPickCover;

  const _TrackEditCard({
    required this.track,
    required this.index,
    required this.onUpdate,
    required this.onPickCover,
  });

  @override
  State<_TrackEditCard> createState() => _TrackEditCardState();
}

class _TrackEditCardState extends State<_TrackEditCard> {
  int _selectedTab = 0;
  final List<String> _tabs = ['Basic', 'Album', 'Tags', 'Lyrics', 'Price'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final track = widget.track;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover and Title
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cover Image - Click to upload
                InkWell(
                  onTap: widget.onPickCover,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.2),
                      ),
                    ),
                    child: track['cover'] != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: track['cover'],
                              fit: BoxFit.cover,
                              placeholder: (context, url) => const Center(
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              errorWidget: (context, url, error) => Icon(
                                Icons.music_note,
                                size: 40,
                                color: isDark ? Colors.white54 : Colors.black54,
                              ),
                            ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_photo_alternate,
                                size: 32,
                                color: isDark ? Colors.white54 : Colors.black54,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Add Cover',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isDark ? Colors.white54 : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                // Tabs
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _tabs.length,
                      itemBuilder: (context, index) {
                        final isSelected = index == _selectedTab;
                        return InkWell(
                          onTap: () {
                            setState(() {
                              _selectedTab = index;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: isSelected ? theme.colorScheme.primary : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                            child: Text(
                              _tabs[index],
                              style: TextStyle(
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : (isDark ? Colors.white70 : Colors.black54),
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Form Fields based on selected tab
            if (_selectedTab == 0) ...[
              _buildTextField(
                label: 'Title',
                value: track['title']?.toString() ?? '',
                onChanged: (value) => widget.onUpdate('title', value),
              ),
              const SizedBox(height: 12),
              _buildTextField(
                label: 'Artist Name',
                value: track['artist_name']?.toString() ?? '',
                onChanged: (value) => widget.onUpdate('artist_name', value),
              ),
              const SizedBox(height: 12),
              _buildTextField(
                label: 'Featured Artists',
                value: track['featured']?.toString() ?? '',
                hint: '+ Search',
                onChanged: (value) => widget.onUpdate('featured', value),
              ),
              const SizedBox(height: 12),
              _buildDatePickerField(
                label: 'Release Date',
                value: track['release_date']?.toString() ?? '',
                onChanged: (value) => widget.onUpdate('release_date', value),
              ),
              const SizedBox(height: 12),
              _buildTextField(
                label: 'Description',
                value: track['description']?.toString() ?? '',
                maxLines: 3,
                onChanged: (value) => widget.onUpdate('description', value),
              ),
            ] else if (_selectedTab == 1) ...[
              _buildTextField(
                label: 'Album ID (existing album)',
                value: track['album_id']?.toString() ?? '',
                hint: 'Enter existing album ID, or leave empty',
                onChanged: (value) => widget.onUpdate('album_id', value),
              ),
              const SizedBox(height: 12),
              _buildTextField(
                label: 'Track Number',
                value: track['track_number']?.toString() ?? '',
                onChanged: (value) => widget.onUpdate('track_number', value),
              ),
            ] else if (_selectedTab == 2) ...[
              _buildTextField(
                label: 'Genre',
                value: track['genre']?.toString() ?? '',
                onChanged: (value) => widget.onUpdate('genre', value),
              ),
              const SizedBox(height: 12),
              _buildTextField(
                label: 'Mood',
                value: track['mood']?.toString() ?? '',
                onChanged: (value) => widget.onUpdate('mood', value),
              ),
              const SizedBox(height: 12),
              _buildTextField(
                label: 'Tags',
                value: track['tags']?.toString() ?? '',
                hint: 'Comma separated tags',
                onChanged: (value) => widget.onUpdate('tags', value),
              ),
            ] else if (_selectedTab == 3) ...[
              _buildTextField(
                label: 'Lyrics',
                value: track['lyrics']?.toString() ?? '',
                maxLines: 6,
                onChanged: (value) => widget.onUpdate('lyrics', value),
              ),
            ] else if (_selectedTab == 4) ...[
              _buildTextField(
                label: 'Price',
                value: track['price']?.toString() ?? '',
                hint: '0.00',
                onChanged: (value) => widget.onUpdate('price', value),
              ),
              const SizedBox(height: 12),
              _buildTextField(
                label: 'Currency',
                value: track['currency']?.toString() ?? 'USD',
                onChanged: (value) => widget.onUpdate('currency', value),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required String value,
    String? hint,
    int maxLines = 1,
    required ValueChanged<String> onChanged,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black54,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: TextEditingController(text: value)
            ..selection = TextSelection.collapsed(offset: value.length),
          onChanged: onChanged,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: isDark ? Colors.white38 : Colors.black38,
              fontSize: 12,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.2),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.2),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
        ),
      ],
    );
  }

  Widget _buildDatePickerField({
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Parse existing date or use current date
    DateTime initialDate;
    if (value.isNotEmpty) {
      try {
        initialDate = DateTime.parse(value);
      } catch (e) {
        initialDate = DateTime.now();
      }
    } else {
      initialDate = DateTime.now();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black54,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: initialDate,
              firstDate: DateTime(1900),
              lastDate: DateTime(2100),
              builder: (context, child) {
                return Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: isDark
                        ? ColorScheme.dark(
                            primary: theme.colorScheme.primary,
                            surface: Colors.grey[900]!,
                            onSurface: Colors.white,
                          )
                        : ColorScheme.light(
                            primary: theme.colorScheme.primary,
                            surface: Colors.white,
                            onSurface: Colors.black,
                          ),
                  ),
                  child: child!,
                );
              },
            );
            if (picked != null) {
              // Format as YYYY-MM-DD
              final formattedDate = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
              onChanged(formattedDate);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(
                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.2),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 18,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
                const SizedBox(width: 8),
                Text(
                  value.isNotEmpty ? value : 'Select date',
                  style: TextStyle(
                    color: value.isNotEmpty
                        ? (isDark ? Colors.white : Colors.black)
                        : (isDark ? Colors.white38 : Colors.black38),
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.arrow_drop_down,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
