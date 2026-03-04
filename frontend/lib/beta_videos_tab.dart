import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';

class BetaVideosPage extends StatefulWidget {
  final String climbId;
  final String climbName;
  final bool isCreator;

  const BetaVideosPage({
    super.key,
    required this.climbId,
    required this.climbName,
    required this.isCreator,
  });

  @override
  State<BetaVideosPage> createState() => _BetaVideosPageState();
}

class _BetaVideosPageState extends State<BetaVideosPage> {
  List<Map<String, dynamic>> _videos = [];
  bool _loading = true;
  bool _uploading = false;
  bool _compressing = false;

  @override
  void initState() {
    super.initState();
    _fetchVideos();
  }

  Future<void> _fetchVideos() async {
    try {
      final response = await Supabase.instance.client
          .from('beta_videos')
          .select()
          .eq('climbid', widget.climbId)
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _videos = List<Map<String, dynamic>>.from(response);
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching beta videos: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _uploadVideo() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final picker = ImagePicker();
    XFile? picked;
    try {
      picked = await picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 3),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video picker unavailable on simulator — test on a real device.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    if (picked == null) return;

    setState(() => _compressing = true);

    File file;
    try {
      final info = await VideoCompress.compressVideo(
        picked.path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
      );
      file = info?.file ?? File(picked.path);
    } catch (e) {
      debugPrint('Compression failed, using original: $e');
      file = File(picked.path);
    } finally {
      if (mounted) setState(() => _compressing = false);
    }

    final fileSize = await file.length();
    if (fileSize > 200 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video must be under 200 MB'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _uploading = true);

    try {
      final displayName = user.userMetadata?['display_name'] ?? 'Unknown';
      final ts = DateTime.now().millisecondsSinceEpoch;
      final storagePath = '${widget.climbId}/${user.id}_$ts.mp4';

      await Supabase.instance.client.storage
          .from('beta-videos')
          .upload(
            storagePath,
            file,
            fileOptions: const FileOptions(contentType: 'video/mp4'),
          );

      final publicUrl = Supabase.instance.client.storage
          .from('beta-videos')
          .getPublicUrl(storagePath);

      // Generate and upload first-frame thumbnail
      String? thumbnailUrl;
      try {
        final thumbBytes = await VideoCompress.getByteThumbnail(
          file.path,
          quality: 75,
          position: -1,
        );
        if (thumbBytes != null) {
          final thumbPath = '${widget.climbId}/${user.id}_${ts}_thumb.jpg';
          await Supabase.instance.client.storage
              .from('beta-videos')
              .uploadBinary(
                thumbPath,
                thumbBytes,
                fileOptions: const FileOptions(contentType: 'image/jpeg'),
              );
          thumbnailUrl = Supabase.instance.client.storage
              .from('beta-videos')
              .getPublicUrl(thumbPath);
        }
      } catch (e) {
        debugPrint('Thumbnail generation failed: $e');
      }

      await Supabase.instance.client.from('beta_videos').insert({
        'climbid': widget.climbId,
        'user_id': user.id,
        'username': displayName,
        'storage_path': storagePath,
        'public_url': publicUrl,
        'thumbnail_url': thumbnailUrl,
      });

      await _fetchVideos();
    } catch (e) {
      debugPrint('Error uploading video: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _deleteVideo(Map<String, dynamic> video) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete video?'),
        content: const Text('This will permanently remove the beta video.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final storagePath = video['storage_path'] as String;
      final thumbPath = storagePath.replaceAll('.mp4', '_thumb.jpg');
      await Supabase.instance.client.storage
          .from('beta-videos')
          .remove([storagePath, thumbPath]);
      await Supabase.instance.client
          .from('beta_videos')
          .delete()
          .eq('id', video['id']);
      await _fetchVideos();
    } catch (e) {
      debugPrint('Error deleting video: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(title: Text('Beta — ${widget.climbName}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: (_uploading || _compressing) ? null : _uploadVideo,
        icon: (_uploading || _compressing)
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.upload_rounded),
        label: Text(_compressing ? 'Compressing...' : _uploading ? 'Uploading...' : 'Upload Beta'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _videos.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam_off_outlined, size: 48, color: Colors.grey),
                      SizedBox(height: 12),
                      Text(
                        'No beta videos yet.',
                        style: TextStyle(color: Colors.grey),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Be the first to upload!',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: _videos.length,
                  itemBuilder: (context, index) {
                    final video = _videos[index];
                    final canDelete =
                        widget.isCreator || video['user_id'] == currentUserId;

                    final thumbUrl = video['thumbnail_url'] as String?;

                    return GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _VideoPlayerPage(
                            url: video['public_url'] as String,
                            uploaderName: video['username'] ?? 'Unknown',
                          ),
                        ),
                      ),
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Thumbnail area
                            Expanded(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  thumbUrl != null
                                      ? Image.network(
                                          thumbUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              Container(color: Colors.grey.shade900),
                                        )
                                      : Container(color: Colors.grey.shade900),
                                  const Center(
                                    child: Icon(
                                      Icons.play_circle_outline,
                                      size: 48,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Info row
                            Padding(
                              padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          video['username'] ?? 'Unknown',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          _formatDate(video['created_at']),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (canDelete)
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 18),
                                      color: Colors.grey,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () => _deleteVideo(video),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

// ── Full-screen video player ──────────────────────────────────────────────────

class _VideoPlayerPage extends StatefulWidget {
  final String url;
  final String uploaderName;

  const _VideoPlayerPage({required this.url, required this.uploaderName});

  @override
  State<_VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<_VideoPlayerPage> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _showControls = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller.initialize().then((_) {
      if (mounted) {
        setState(() => _initialized = true);
        _controller.play();
        _scheduleHide();
      }
    });
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _onTap() {
    if (!_showControls) {
      setState(() => _showControls = true);
      if (_controller.value.isPlaying) _scheduleHide();
      return;
    }
    if (_controller.value.isPlaying) {
      _controller.pause();
      _hideTimer?.cancel();
    } else {
      _controller.play();
      _scheduleHide();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        toolbarHeight: 36,
      ),
      body: !_initialized
          ? const Center(child: CircularProgressIndicator())
          : GestureDetector(
              onTap: _onTap,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    ),
                  ),
                  // Play/pause icon
                  AnimatedOpacity(
                    opacity: _showControls ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.black38,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Icon(
                        _controller.value.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                        color: Colors.white,
                        size: 52,
                      ),
                    ),
                  ),
                  // Progress bar
                  Positioned(
                    bottom: 70,
                    left: 0,
                    right: 0,
                    child: AnimatedOpacity(
                      opacity: _showControls ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: SizedBox(
                        height: 28,
                        child: VideoProgressIndicator(
                          _controller,
                          allowScrubbing: true,
                          colors: VideoProgressColors(
                            playedColor: Theme.of(context).colorScheme.primary,
                            bufferedColor: Colors.white30,
                            backgroundColor: Colors.white12,
                          ),
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
