import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

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

    final file = File(picked.path);
    final fileSize = await file.length();
    if (fileSize > 100 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video must be under 100 MB'),
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

      await Supabase.instance.client.from('beta_videos').insert({
        'climbid': widget.climbId,
        'user_id': user.id,
        'username': displayName,
        'storage_path': storagePath,
        'public_url': publicUrl,
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
      await Supabase.instance.client.storage
          .from('beta-videos')
          .remove([video['storage_path'] as String]);
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
        onPressed: _uploading ? null : _uploadVideo,
        icon: _uploading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.upload_rounded),
        label: Text(_uploading ? 'Uploading...' : 'Upload Beta'),
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
                              child: Container(
                                color: Colors.grey.shade900,
                                child: const Center(
                                  child: Icon(
                                    Icons.play_circle_outline,
                                    size: 48,
                                    color: Colors.white70,
                                  ),
                                ),
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
  late VideoPlayerController _videoController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    _videoController =
        VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _videoController.initialize().then((_) {
      if (mounted) {
        setState(() {
          _chewieController = ChewieController(
            videoPlayerController: _videoController,
            autoPlay: true,
            looping: false,
            aspectRatio: _videoController.value.aspectRatio,
            allowFullScreen: true,
            allowMuting: true,
          );
        });
      }
    });
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Beta by ${widget.uploaderName}'),
      ),
      body: Center(
        child: _chewieController != null
            ? Chewie(controller: _chewieController!)
            : const CircularProgressIndicator(),
      ),
    );
  }
}
