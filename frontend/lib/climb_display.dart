import 'holds.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'climb_update.dart';

// Original image width x height in pixels
const double originalImageWidth = 5712;
const double originalImageHeight = 4284;

class ClimbDisplay extends StatefulWidget {
  final String climbId;

  const ClimbDisplay({super.key, required this.climbId});

  @override
  State<ClimbDisplay> createState() => _ClimbDisplayState();
}

class _ClimbDisplayState extends State<ClimbDisplay> {
  late List<HtmlMapHold> holdsList;
  List<Map<String, dynamic>> ascents = [];
  bool loading = true;
  String? error;

  String climbName = '';
  String displayName = '';
  String climbGrade = '';
  String notes = '';
  String? createdByDisplayName;
  bool isCurrentUserCreator = false;
  bool isPrivate = false; // Added for private status

  @override
  void initState() {
    super.initState();
    holdsList = holds.map((h) => HtmlMapHold(h.points)).toList();
    _fetchClimbData();
  }

  @override
  void dispose() {
    for (final hold in holdsList) {
      hold.selected = 0;
    }
    super.dispose();
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

      // Update the climbs table with the new ascents array
      await Supabase.instance.client
          .from('climbs')
          .update({'ascents': currentAscents}).eq('climbid', widget.climbId);

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

  @override
  Widget build(BuildContext context) {
    final imageAspectRatio = originalImageWidth / originalImageHeight;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                climbName.isEmpty
                    ? 'Loading...'
                    : climbGrade.isEmpty
                        ? climbName
                        : '$climbName | $climbGrade',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Show lock icon if private
            if (isPrivate && !loading) ...[
              const SizedBox(width: 6),
              const Icon(Icons.lock, size: 18),
            ],
          ],
        ),
        actions: [
          IconButton(
    icon: const Icon(Icons.info_outline),
    tooltip: "Hold Info",
    onPressed: () => _showInfoDialog(context),
  ),
          if (isCurrentUserCreator)
            IconButton(
              icon: const Icon(Icons.settings),
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
                      final imageAreaHeight = maxHeight * 2 / 3;
                      final ascentsAreaHeight = maxHeight / 3;

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
                                ElevatedButton.icon(
                                  onPressed: () {
                                    final initialGrade = int.tryParse(
                                          climbGrade.replaceAll(
                                              RegExp(r'[vV]'), ''),
                                        ) ??
                                        0;
                                    _sendForm(context, initialGrade);
                                  },
                                  icon: const Icon(Icons.add),
                                  label: const Text('Log Ascent'),
                                ),
                                const SizedBox(height: 12),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      if (displayName.isNotEmpty)
                                        Text(
                                          'Set by: $displayName',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey.shade700,
                                            fontSize: 15,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      if (notes.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          notes,
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 12,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const Divider(height: 1, thickness: 1),

                          // BOTTOM 1/3: Ascents List
                          SizedBox(
                            height: ascentsAreaHeight - 1,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.people_outline,
                                          size: 20),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Ascents (${ascents.length})',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: ascents.isEmpty
                                      ? const Center(
                                          child: Text(
                                            'No ascents yet. Be the first!',
                                            style:
                                                TextStyle(color: Colors.grey),
                                          ),
                                        )
                                      : ListView.separated(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12),
                                          itemCount: ascents.length,
                                          separatorBuilder: (_, __) =>
                                              const SizedBox(height: 8),
                                          itemBuilder: (context, index) {
                                            final ascent = ascents[index];
                                            final username =
                                                ascent['username'] ?? 'Unknown';
                                            final gradeFeel =
                                                ascent['grade_feel'];
                                            final attempts = ascent['attempts'];
                                            final isFlash =
                                                ascent['is_flash'] ?? false;
                                            final timestamp =
                                                ascent['timestamp'];

                                            return Card(
                                              margin: EdgeInsets.zero,
                                              child: ListTile(
                                                leading: CircleAvatar(
                                                  child: Text(
                                                    username.toString().isNotEmpty
                                                        ? username
                                                            .toString()[0]
                                                            .toUpperCase()
                                                        : '?',
                                                  ),
                                                ),
                                                title: Row(
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        username.toString(),
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                    if (isFlash) ...[
                                                      const SizedBox(width: 6),
                                                      const Icon(
                                                        Icons.flash_on,
                                                        color: Colors.amber,
                                                        size: 18,
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                                subtitle: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    if (attempts != null)
                                                      Text(
                                                        _getAttemptsDisplayText(
                                                            attempts),
                                                        style: TextStyle(
                                                          color: Colors
                                                              .grey.shade600,
                                                        ),
                                                      ),
                                                    if (timestamp != null)
                                                      Text(
                                                        _formatTimestamp(
                                                            timestamp),
                                                        style: TextStyle(
                                                          color: Colors
                                                              .grey.shade500,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                                trailing: gradeFeel != null
                                                    ? Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 8,
                                                          vertical: 4,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: Colors.blue
                                                              .withOpacity(0.1),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(8),
                                                        ),
                                                        child: Text(
                                                          'V$gradeFeel',
                                                          style:
                                                              const TextStyle(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color: Colors.blue,
                                                          ),
                                                        ),
                                                      )
                                                    : null,
                                              ),
                                            );
                                          },
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
                        min: 0,
                        max: 17,
                        divisions: 17,
                        label: 'V$gradeSliderValue',
                        onChanged: (newValue) {
                          setModalState(() {
                            gradeSliderValue = newValue.round();
                          });
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('Grade: V$gradeSliderValue'),
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

                      _insertSend(attemptsValue, gradeSliderValue);
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
          1 => Colors.blue.withOpacity(0.5),
          2 => Colors.orange.withOpacity(0.5),
          3 => Colors.green.withOpacity(0.5),
          4 => Colors.purple.withOpacity(0.5),
          _ => Colors.transparent,
        }
        ..style = PaintingStyle.fill;

      final strokePaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _HtmlMapPainter oldDelegate) => true;
}