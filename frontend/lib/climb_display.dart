import 'holds.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'climb_update.dart';
import 'Profile.dart';

// Original image width x height in pixels
const double originalImageWidth = 5712;
const double originalImageHeight = 4284;

class ClimbDisplay extends StatefulWidget {
  final String climbId;

  const ClimbDisplay({super.key, required this.climbId});

  @override
  State<ClimbDisplay> createState() => _ClimbDisplayState();
}

class _ClimbDisplayState extends State<ClimbDisplay>
    with TickerProviderStateMixin {
  late List<HtmlMapHold> holdsList;
  late TabController _tabController;
  List<Map<String, dynamic>> ascents = [];
  List<Map<String, dynamic>> comments = [];
  bool loading = true;
  String? error;

  String climbName = '';
  String displayName = '';
  String climbGrade = '';
  String notes = '';
  String? createdByDisplayName;
  bool isCurrentUserCreator = false;
  bool isPrivate = false;
  bool _isSaved = false;
  bool _isLiked = false;
  Set<String> _likerIds = {};

  @override
  void initState() {
    super.initState();
    holdsList = holds.map((h) => HtmlMapHold(h.points)).toList();
    _tabController = TabController(length: 2, vsync: this);
    _fetchClimbData();
    _checkIfSaved();
    _checkIfLiked();
    _fetchComments();
  }

  Future<void> _checkIfLiked() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final myLike = await Supabase.instance.client
          .from('liked_climbs')
          .select('id')
          .eq('user_id', userId)
          .eq('climbid', widget.climbId)
          .maybeSingle();
      final allLikes = await Supabase.instance.client
          .from('liked_climbs')
          .select('user_id')
          .eq('climbid', widget.climbId);
      if (mounted) {
        setState(() {
          _isLiked = myLike != null;
          _likerIds = List<Map<String, dynamic>>.from(allLikes)
              .map((r) => r['user_id'].toString())
              .toSet();
        });
      }
    } catch (e) {
      debugPrint('Error checking liked status: $e');
    }
  }

  Future<void> _toggleLike() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final wasLiked = _isLiked;
    setState(() {
      _isLiked = !_isLiked;
      if (wasLiked) {
        _likerIds.remove(userId);
      } else {
        _likerIds.add(userId);
      }
    });
    try {
      if (wasLiked) {
        await Supabase.instance.client
            .from('liked_climbs')
            .delete()
            .eq('user_id', userId)
            .eq('climbid', widget.climbId);
      } else {
        await Supabase.instance.client
            .from('liked_climbs')
            .insert({'user_id': userId, 'climbid': widget.climbId, 'setter_name': createdByDisplayName});
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLiked = wasLiked;
          if (wasLiked) {
            _likerIds.add(userId);
          } else {
            _likerIds.remove(userId);
          }
        });
      }
      debugPrint('Error toggling like: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final hold in holdsList) {
      hold.selected = 0;
    }
    super.dispose();
  }

  Future<void> _checkIfSaved() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final response = await Supabase.instance.client
          .from('saved_climbs')
          .select('id')
          .eq('user_id', userId)
          .eq('climbid', widget.climbId)
          .maybeSingle();
      if (mounted) setState(() => _isSaved = response != null);
    } catch (e) {
      debugPrint('Error checking saved status: $e');
    }
  }

  Future<void> _toggleSave() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final wasSaved = _isSaved;
    setState(() => _isSaved = !_isSaved);
    try {
      if (wasSaved) {
        await Supabase.instance.client
            .from('saved_climbs')
            .delete()
            .eq('user_id', userId)
            .eq('climbid', widget.climbId);
      } else {
        await Supabase.instance.client
            .from('saved_climbs')
            .insert({'user_id': userId, 'climbid': widget.climbId});
      }
    } catch (e) {
      if (mounted) setState(() => _isSaved = wasSaved);
      debugPrint('Error toggling save: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _insertSend(int? attempts, int? gradeFeel) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final displayName = user.userMetadata?['display_name'] ?? 'Unknown';

    try {
      // Create the new ascent object
      final newAscent = {
        'user_id': user.id,
        'username': displayName,
        'attempts': attempts,
        'grade_feel': gradeFeel,
        'is_flash': attempts == 0,
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Fetch current ascents from the climb
      final climbResponse = await Supabase.instance.client
          .from('climbs')
          .select('ascents')
          .eq('climbid', widget.climbId)
          .maybeSingle();

      // Get existing ascents or create empty list
      List<dynamic> currentAscents = [];
      if (climbResponse != null && climbResponse['ascents'] != null) {
        currentAscents = List<dynamic>.from(climbResponse['ascents']);
      }

      // Add the new ascent
      currentAscents.add(newAscent);

      // sends = number of unique users who have sent this climb
      final uniqueSends = currentAscents.map((a) => a['user_id']).toSet().length;

      // Update the climbs table with the new ascents array and send count
      await Supabase.instance.client
          .from('climbs')
          .update({'ascents': currentAscents, 'sends': uniqueSends})
          .eq('climbid', widget.climbId);

      await _fetchAscents();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ascent logged!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error inserting send: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _fetchAscents() async {
    try {
      final response = await Supabase.instance.client
          .from('climbs')
          .select('ascents')
          .eq('climbid', widget.climbId)
          .maybeSingle();

      if (response != null && response['ascents'] != null) {
        final List<dynamic> ascentsJson = response['ascents'];

        // Sort by timestamp descending (newest first)
        ascentsJson.sort((a, b) {
          final timestampA = a['timestamp'] ?? '';
          final timestampB = b['timestamp'] ?? '';
          return timestampB.compareTo(timestampA);
        });

        setState(() {
          ascents = List<Map<String, dynamic>>.from(ascentsJson);
        });
      } else {
        setState(() {
          ascents = [];
        });
      }
    } catch (e) {
      debugPrint("Error fetching ascents: $e");
    }
  }

  Future<void> _fetchClimbData() async {
    try {
      // Fetch climb data including holds JSONB column and private field
      final climbResponse = await Supabase.instance.client
          .from('climbs')
          .select('name, grade, holds, displayname, notes, private, ascents')
          .eq('climbid', widget.climbId)
          .maybeSingle();

      if (climbResponse != null) {
        climbName = climbResponse['name'] ?? 'Unnamed Climb';
        climbGrade = climbResponse['grade'] ?? '';
        displayName = climbResponse['displayname'] ?? '';
        notes = climbResponse['notes'] ?? '';
        createdByDisplayName = climbResponse['displayname'] ?? '';
        isPrivate = climbResponse['private'] == true;

        final user = Supabase.instance.client.auth.currentUser;
        final currentDisplayName = user?.userMetadata?['display_name'] ?? 'Unknown';
        isCurrentUserCreator = currentDisplayName == createdByDisplayName;

        // Parse holds from JSONB
        final holdsJson = climbResponse['holds'];
        if (holdsJson != null) {
          final List<dynamic> holdsList = holdsJson is List ? holdsJson : [];
          for (final holdData in holdsList) {
            final int arrayIndex = holdData['array_index'] ?? -1;
            final int holdState = holdData['holdstate'] ?? 0;
            if (arrayIndex >= 0 && arrayIndex < this.holdsList.length) {
              this.holdsList[arrayIndex].selected = holdState;
            }
          }
        }

        // Parse ascents inline — no second network call needed
        final ascentsJson = climbResponse['ascents'];
        if (ascentsJson != null) {
          final List<dynamic> ascentsData = List<dynamic>.from(ascentsJson);
          ascentsData.sort((a, b) {
            final timestampA = a['timestamp'] ?? '';
            final timestampB = b['timestamp'] ?? '';
            return timestampB.compareTo(timestampA);
          });
          ascents = List<Map<String, dynamic>>.from(ascentsData);
        } else {
          ascents = [];
        }
      }

      setState(() {
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = 'Error fetching climb: $e';
        loading = false;
      });
    }
  }

  Future<void> _togglePrivacy() async {
    try {
      final newPrivateStatus = !isPrivate;

      await Supabase.instance.client
          .from('climbs')
          .update({'private': newPrivateStatus})
          .eq('climbid', widget.climbId);

      setState(() {
        isPrivate = newPrivateStatus;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newPrivateStatus
                  ? '🔒 Climb is now private'
                  : '🌐 Climb is now public',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error toggling privacy: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating privacy: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  String _getAttemptsDisplayText(int? attempts) {
    if (attempts == null) return '';
    if (attempts == 0) return 'Flash';
    if (attempts == 31) return '30+ attempts';
    return '$attempts attempt${attempts == 1 ? '' : 's'}';
  }

  String _formatTimestamp(String? timestamp) {
    if (timestamp == null) return '';
    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inDays == 0) {
        if (difference.inHours == 0) {
          if (difference.inMinutes == 0) {
            return 'Just now';
          }
          return '${difference.inMinutes}m ago';
        }
        return '${difference.inHours}h ago';
      } else if (difference.inDays == 1) {
        return 'Yesterday';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
      }
    } catch (e) {
      return '';
    }
  }

  void _showClimbSettings() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Climb Settings',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.edit),
                    title: const Text('Update Climb'),
                    onTap: () async {
                      Navigator.pop(context);
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ClimbUpdatePage(climbId: widget.climbId),
                        ),
                      );
                      // If update was successful, refresh the climb data
                      if (result == true) {
                        _fetchClimbData();
                      }
                    },
                  ),
                  // Privacy toggle option
                  ListTile(
                    leading: Icon(
                      isPrivate ? Icons.lock_open : Icons.lock,
                      color: isPrivate ? Colors.green : Colors.orange,
                    ),
                    title: Text(
                      isPrivate ? 'Make Public' : 'Make Private',
                      style: TextStyle(
                        color: isPrivate ? Colors.green : Colors.orange,
                      ),
                    ),
                    subtitle: Text(
                      isPrivate
                          ? 'Currently only visible to you'
                          : 'Currently visible to everyone',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    trailing: Switch(
                      value: isPrivate,
                      onChanged: (value) async {
                        await _togglePrivacy();
                        setModalState(() {}); // Update modal UI
                      },
                      activeColor: Colors.orange,
                    ),
                    onTap: () async {
                      await _togglePrivacy();
                      setModalState(() {}); // Update modal UI
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.delete, color: Colors.red),
                    title: const Text('Delete Climb', style: TextStyle(color: Colors.red)),
                    onTap: () {
                      Navigator.pop(context);
                      _showDeleteConfirmation();
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showInfoDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Hold Info'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Must have at least 1 start and 1 finish hold.\n'),
            Text('blue = hand'),
            Text('orange = foot'),
            Text('green = start'),
            Text('purple = finish'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}


  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Climb'),
        content: Text(
          'Are you sure you want to delete "$climbName"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteClimb();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteClimb() async {
    try {
      await Supabase.instance.client
          .from('climbs')
          .delete()
          .eq('climbid', widget.climbId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Climb deleted successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.pop(context); // Go back to previous screen
      }
    } catch (e) {
      debugPrint("Error deleting climb: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting climb: $e'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _deleteAscent(int index) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final climbResponse = await Supabase.instance.client
          .from('climbs')
          .select('ascents')
          .eq('climbid', widget.climbId)
          .maybeSingle();
      if (climbResponse == null) return;

      final target = ascents[index];
      final List<dynamic> currentAscents =
          List<dynamic>.from(climbResponse['ascents'] ?? []);
      currentAscents.removeWhere((a) =>
          a['user_id'] == target['user_id'] &&
          a['timestamp'] == target['timestamp']);

      final uniqueSends =
          currentAscents.map((a) => a['user_id']).toSet().length;

      await Supabase.instance.client
          .from('climbs')
          .update({'ascents': currentAscents, 'sends': uniqueSends})
          .eq('climbid', widget.climbId);

      await _fetchAscents();
    } catch (e) {
      debugPrint('Error deleting ascent: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _fetchComments() async {
    try {
      final response = await Supabase.instance.client
          .from('comments')
          .select()
          .eq('climbid', widget.climbId)
          .order('createdat', ascending: true);
      if (mounted) {
        setState(() {
          comments = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      debugPrint('Error fetching comments: $e');
    }
  }

  Future<void> _addComment(String content) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final username = user.userMetadata?['display_name'] ?? 'Unknown';
    try {
      await Supabase.instance.client.from('comments').insert({
        'climbid': widget.climbId,
        'user_id': user.id,
        'username': username,
        'content': content,
      });
      await _fetchComments();
    } catch (e) {
      debugPrint('Error adding comment: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteComment(String commentId) async {
    try {
      await Supabase.instance.client
          .from('comments')
          .delete()
          .eq('id', commentId);
      await _fetchComments();
    } catch (e) {
      debugPrint('Error deleting comment: $e');
    }
  }

  void _showCommentInput() {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Wrap(
          children: [
            Text('Add Comment',
                style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12, width: double.infinity),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Write a comment...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12, width: double.infinity),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    final text = controller.text.trim();
                    if (text.isEmpty) return;
                    Navigator.pop(ctx);
                    _addComment(text);
                  },
                  child: const Text('Post'),
                ),
              ],
            ),
            const SizedBox(height: 16, width: double.infinity),
          ],
        ),
      ),
    );
  }

  // Grade: ceiling average of all ascents' grade_feel, falling back to setter grade if none.
  String get _gradeLabel {
    final grades = ascents
        .map((a) => a['grade_feel'])
        .whereType<num>()
        .map((g) => g.toInt())
        .toList();
    if (grades.isEmpty) return climbGrade.isEmpty ? '?' : climbGrade;
    final avg = grades.reduce((a, b) => a + b) / grades.length;
    return 'V${avg.ceil()}';
  }

  @override
  Widget build(BuildContext context) {
    final imageAspectRatio = originalImageWidth / originalImageHeight;
    final grade = _gradeLabel;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    loading ? 'Loading...' : climbName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
                if (isPrivate && !loading) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.lock, size: 14),
                ],
              ],
            ),
            if (!loading) ...[
              GestureDetector(
                onTap: createdByDisplayName != null
                    ? () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => UserProfilePage(displayName: createdByDisplayName!),
                          ),
                        )
                    : null,
                child: Text.rich(
                  TextSpan(
                    text: 'Set by: ',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
                    children: [
                      TextSpan(
                        text: createdByDisplayName ?? 'Unknown',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                'Grade: $grade',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, size: 18),
            tooltip: "Hold Info",
            onPressed: () => _showInfoDialog(context),
          ),
          if (isCurrentUserCreator)
            IconButton(
              icon: const Icon(Icons.settings, size: 18),
              tooltip: "Climb Settings",
              onPressed: _showClimbSettings,
            ),
        ],
      ),
      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? Center(child: Text(error!))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final maxWidth = constraints.maxWidth;
                      final maxHeight = constraints.maxHeight;

                      // Image section: 2/3, Ascents section: 1/3
                      final imageAreaHeight = maxHeight * 0.60;
                      final ascentsAreaHeight = maxHeight * 0.40;

                      final maxDisplayWidth =
                          maxWidth > 800 ? 800.0 : maxWidth;

                      double displayedWidth;
                      double displayedHeight;

                      final widthBasedHeight =
                          maxDisplayWidth / imageAspectRatio;

                      if (widthBasedHeight <= imageAreaHeight - 70) {
                        displayedWidth = maxDisplayWidth;
                        displayedHeight = widthBasedHeight;
                      } else {
                        displayedHeight = imageAreaHeight - 70;
                        displayedWidth = displayedHeight * imageAspectRatio;
                      }

                      final scaleX = displayedWidth / originalImageWidth;
                      final scaleY = displayedHeight / originalImageHeight;
                      final fontScale = displayedWidth / 1500;

                      return Column(
                        children: [
                          // TOP 2/3: Image + Log Button
                          SizedBox(
                            height: imageAreaHeight,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                const SizedBox(height: 8),
                                Center(
                                  child: InteractiveViewer(
                                    panEnabled: true,
                                    scaleEnabled: true,
                                    minScale: 1.0,
                                    maxScale: 5.0,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Image.asset(
                                          'assets/spray_wall.jpeg',
                                          width: displayedWidth,
                                          height: displayedHeight,
                                          fit: BoxFit.contain,
                                          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                                            if (wasSynchronouslyLoaded || frame != null) return child;
                                            return SizedBox(
                                              width: displayedWidth,
                                              height: displayedHeight,
                                              child: const Center(child: CircularProgressIndicator()),
                                            );
                                          },
                                        ),
                                        CustomPaint(
                                          size: Size(
                                              displayedWidth, displayedHeight),
                                          painter: _HtmlMapPainter(
                                            holdsList,
                                            scaleX,
                                            scaleY,
                                            fontScale,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        _isLiked ? Icons.favorite : Icons.favorite_border,
                                        color: _isLiked ? Colors.red : null,
                                      ),
                                      tooltip: _isLiked ? 'Unlike' : 'Like',
                                      onPressed: _toggleLike,
                                    ),
                                    Expanded(
                                      child: Center(
                                        child: ElevatedButton.icon(
                                          onPressed: () {
                                            final initialGrade = climbGrade == '?'
                                                ? -1
                                                : int.tryParse(climbGrade.replaceAll(
                                                        RegExp(r'[vV]'), '')) ??
                                                    0;
                                            _sendForm(context, initialGrade);
                                          },
                                          icon: const Icon(Icons.add),
                                          label: const Text('Log Ascent'),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        _isSaved ? Icons.bookmark : Icons.bookmark_outline,
                                        color: _isSaved ? Colors.deepOrange : null,
                                      ),
                                      tooltip: _isSaved ? 'Unsave climb' : 'Save climb',
                                      onPressed: _toggleSave,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                if (notes.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: Text(
                                      notes,
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          // BOTTOM 1/3: Ascents / Comments tabs
                          SizedBox(
                            height: ascentsAreaHeight,
                            child: Column(
                              children: [
                                TabBar(
                                  controller: _tabController,
                                  tabs: [
                                    Tab(text: 'Ascents (${ascents.length})'),
                                    Tab(text: 'Comments (${comments.length})'),
                                  ],
                                ),
                                Expanded(
                                  child: TabBarView(
                                    controller: _tabController,
                                    children: [
                                      // ── Ascents tab ──
                                      ascents.isEmpty
                                          ? const Center(
                                              child: Text(
                                                'No ascents yet. Be the first!',
                                                style: TextStyle(color: Colors.grey),
                                              ),
                                            )
                                          : ListView.separated(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                              itemCount: ascents.length,
                                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                                              itemBuilder: (context, index) {
                                                final ascent = ascents[index];
                                                final username = ascent['username'] ?? 'Unknown';
                                                final gradeFeel = ascent['grade_feel'];
                                                final attempts = ascent['attempts'];
                                                final isFlash = ascent['is_flash'] ?? false;
                                                final timestamp = ascent['timestamp'];
                                                final currentUserId = Supabase.instance.client.auth.currentUser?.id;
                                                final isOwner = ascent['user_id'] == currentUserId;
                                                final ascentUserLiked = _likerIds.contains(ascent['user_id']?.toString());
                                                return Card(
                                                  margin: EdgeInsets.zero,
                                                  child: ListTile(
                                                    contentPadding: const EdgeInsets.only(left: 16, right: 4),
                                                    leading: CircleAvatar(
                                                      child: Text(
                                                        username.toString().isNotEmpty
                                                            ? username.toString()[0].toUpperCase()
                                                            : '?',
                                                      ),
                                                    ),
                                                    title: Row(
                                                      children: [
                                                        Flexible(
                                                          child: Text(
                                                            username.toString(),
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                        if (ascentUserLiked) ...[
                                                          const SizedBox(width: 6),
                                                          const Icon(Icons.favorite, color: Colors.red, size: 14),
                                                        ],
                                                        if (isFlash) ...[
                                                          const SizedBox(width: 6),
                                                          const Icon(Icons.flash_on, color: Colors.amber, size: 18),
                                                        ],
                                                      ],
                                                    ),
                                                    subtitle: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        if (attempts != null)
                                                          Text(
                                                            _getAttemptsDisplayText(attempts),
                                                            style: TextStyle(color: Colors.grey.shade600),
                                                          ),
                                                        if (timestamp != null)
                                                          Text(
                                                            _formatTimestamp(timestamp),
                                                            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                                                          ),
                                                      ],
                                                    ),
                                                    trailing: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        if (gradeFeel != null)
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                            decoration: BoxDecoration(
                                                              color: Colors.blue.withValues(alpha: 0.1),
                                                              borderRadius: BorderRadius.circular(8),
                                                            ),
                                                            child: Text(
                                                              'V$gradeFeel',
                                                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                                                            ),
                                                          ),
                                                        if (isOwner)
                                                          IconButton(
                                                            icon: const Icon(Icons.delete_outline, size: 18),
                                                            color: Colors.grey,
                                                            padding: EdgeInsets.zero,
                                                            constraints: const BoxConstraints(),
                                                            onPressed: () => _deleteAscent(index),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),

                                      // ── Comments tab ──
                                      Column(
                                        children: [
                                          Expanded(
                                            child: comments.isEmpty
                                                ? const Center(
                                                    child: Text(
                                                      'No comments yet.',
                                                      style: TextStyle(color: Colors.grey),
                                                    ),
                                                  )
                                                : ListView.builder(
                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                    itemCount: comments.length,
                                                    itemBuilder: (context, index) {
                                                      final comment = comments[index];
                                                      final username = comment['username'] ?? 'Unknown';
                                                      final content = comment['content'] ?? '';
                                                      final timestamp = comment['createdat'];
                                                      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
                                                      final isOwner = comment['user_id'] == currentUserId;
                                                      return Card(
                                                        margin: const EdgeInsets.only(bottom: 8),
                                                        child: ListTile(
                                                          leading: CircleAvatar(
                                                            child: Text(
                                                              username.toString().isNotEmpty
                                                                  ? username.toString()[0].toUpperCase()
                                                                  : '?',
                                                            ),
                                                          ),
                                                          title: Text(username.toString()),
                                                          subtitle: Column(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            children: [
                                                              Text(content),
                                                              if (timestamp != null)
                                                                Text(
                                                                  _formatTimestamp(timestamp),
                                                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                                                ),
                                                            ],
                                                          ),
                                                          trailing: isOwner
                                                              ? IconButton(
                                                                  icon: const Icon(Icons.delete_outline, size: 18),
                                                                  color: Colors.grey,
                                                                  onPressed: () => _deleteComment(comment['id']),
                                                                )
                                                              : null,
                                                        ),
                                                      );
                                                    },
                                                  ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                                            child: GestureDetector(
                                              onTap: _showCommentInput,
                                              child: Container(
                                                width: double.infinity,
                                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                                decoration: BoxDecoration(
                                                  border: Border.all(color: Colors.grey.shade300),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  'Add a comment...',
                                                  style: TextStyle(color: Colors.grey.shade500),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
      ),
    );
  }

  void _sendForm(BuildContext context, int initialGrade) {
    int attemptsSliderValue = 1;
    int gradeSliderValue = initialGrade;

    final List<String> attemptLabels = [
      'Flash',
      ...List.generate(30, (i) => '${i + 1}'),
      '30+',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Wrap(
            children: [
              Text(
                'Log Ascent',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16, width: double.infinity),
              StatefulBuilder(
                builder: (context, setModalState) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Number of Attempts
                      const Text(
                        'Number of Attempts',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Slider(
                        value: attemptsSliderValue.toDouble(),
                        min: 0,
                        max: 31,
                        divisions: 31,
                        label: attemptLabels[attemptsSliderValue],
                        onChanged: (newValue) {
                          setModalState(() {
                            attemptsSliderValue = newValue.round();
                          });
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          'Attempts: ${attemptLabels[attemptsSliderValue]}',
                        ),
                      ),

                      // Grade Feel
                      const Text(
                        'Grade Feel',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Slider(
                        value: gradeSliderValue.toDouble(),
                        min: -1,
                        max: 17,
                        divisions: 18,
                        label: gradeSliderValue == -1
                            ? '?'
                            : 'V$gradeSliderValue',
                        onChanged: (newValue) {
                          setModalState(() {
                            gradeSliderValue = newValue.round();
                          });
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Grade: ${gradeSliderValue == -1 ? '?' : 'V$gradeSliderValue'}',
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    child: const Text('Cancel'),
                    onPressed: () => Navigator.pop(context),
                  ),
                  ElevatedButton(
                    child: const Text('Log Send'),
                    onPressed: () {
                      // Convert slider value to database value
                      int? attemptsValue;
                      if (attemptsSliderValue == 0) {
                        attemptsValue = 0; // Flash
                      } else if (attemptsSliderValue == 31) {
                        attemptsValue = 31; // 30+
                      } else {
                        attemptsValue = attemptsSliderValue;
                      }

                      _insertSend(
                        attemptsValue,
                        gradeSliderValue == -1 ? null : gradeSliderValue,
                      );
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16, width: double.infinity),
            ],
          ),
        );
      },
    );
  }
}

class _HtmlMapPainter extends CustomPainter {
  final List<HtmlMapHold> holds;
  final double scaleX;
  final double scaleY;
  final double fontScale;

  _HtmlMapPainter(this.holds, this.scaleX, this.scaleY, this.fontScale);

  @override
  void paint(Canvas canvas, Size size) {
    for (final hold in holds) {
      if (hold.selected == 0) continue;

      final scaledPoints =
          hold.points.map((p) => Offset(p.dx * scaleX, p.dy * scaleY)).toList();

      final path = Path()..addPolygon(scaledPoints, true);

      final fillPaint = Paint()
        ..color = switch (hold.selected) {
          1 => Colors.blue.withValues(alpha: 0.75),
          2 => Colors.orange.withValues(alpha: 0.75),
          3 => Colors.green.withValues(alpha: 0.75),
          4 => Colors.purple.withValues(alpha: 0.75),
          _ => Colors.transparent,
        }
        ..style = PaintingStyle.fill;

      final strokePaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;

      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _HtmlMapPainter oldDelegate) => true;
}