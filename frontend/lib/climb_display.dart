import 'holds.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  int _sliderValue = 0;
  late List<HtmlMapHold> holdsList;
  List<Map<String, dynamic>> holdsArray = [];
  bool loading = true;
  String? error;

  String climbName = '';
  String climbGrade = '';

  @override
  void initState() {
    super.initState();
    holdsList = holds;
    _fetchClimbData();
  }

  @override
  void dispose() {
    for (final hold in holdsList) {
      hold.selected = 0;
    }
    super.dispose();
  }

  Future<void> _insertSend(int grade, String comment, bool flash) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      await Supabase.instance.client.from('climbssent').insert({
        'climbid': widget.climbId,
        'id': user.id,
        'grade': grade,
        'comment': comment.isEmpty ? null : comment,
        'is_flash': flash,
      });

      if (!mounted) return;
      setState(() {}); // optional UI refresh
    } catch (e) {
      print("Error inserting send {$e}");
    }
  }

  Future<void> _fetchClimbData() async {
    try {
      final holdsResponse = await Supabase.instance.client
          .from('climbholds')
          .select()
          .eq('climbid', widget.climbId);
      if (!mounted) return;

      final fetchedHolds = List<Map<String, dynamic>>.from(holdsResponse);

      final climbResponse = await Supabase.instance.client
          .from('climbs')
          .select('name, grade')
          .eq('climbid', widget.climbId)
          .maybeSingle();
      if (!mounted) return;

      if (climbResponse != null) {
        climbName = climbResponse['name'] ?? 'Unnamed Climb';
        climbGrade = climbResponse['grade'] ?? '';
      }

      for (final holdData in fetchedHolds) {
        final int arrayIndex = holdData['array_index'];
        final int holdState = holdData['holdstate'];

        if (arrayIndex >= 0 && arrayIndex < holdsList.length) {
          holdsList[arrayIndex].selected = holdState;
        }
      }

      if (!mounted) return;
      setState(() {
        holdsArray = fetchedHolds;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = 'Error fetching climb: $e';
        loading = false;
      });
    }
  }

  void _sendForm(BuildContext context, int initialGrade) {
    _sliderValue = initialGrade;
    final formKey = GlobalKey<FormState>();
    final commentController = TextEditingController();
    bool isFlash = false;

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
          child: Form(
            key: formKey,
            child: Wrap(
              children: [
                Text('Log send', style: Theme.of(context).textTheme.titleLarge),
                StatefulBuilder(
                  builder: (context, setModalState) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Grade',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Slider(
                          value: _sliderValue.toDouble(),
                          min: 0,
                          max: 17,
                          divisions: 17,
                          label: 'V$_sliderValue',
                          onChanged: (newValue) {
                            setModalState(
                              () => _sliderValue = newValue.round(),
                            );
                          },
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text('Selected Grade: V$_sliderValue'),
                        ),
                        CheckboxListTile(
                          title: const Text("Flash"),
                          value: isFlash,
                          onChanged: (val) =>
                              setModalState(() => isFlash = val ?? false),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: commentController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Comments (optional)',
                            border: OutlineInputBorder(),
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
                      child: const Text('Save'),
                      onPressed: () async {
                        if (formKey.currentState!.validate()) {
                          formKey.currentState!.save();
                          Navigator.pop(context);

                          await _insertSend(
                            _sliderValue,
                            commentController.text,
                            isFlash,
                          );
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _infoForm(BuildContext context) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final creatorResponse = await Supabase.instance.client
          .from('climbs')
          .select('id, grade, displayname')
          .eq('climbid', widget.climbId)
          .maybeSingle();

      if (!mounted) return;

      final displayName = creatorResponse?['displayname'] ?? 'N/A';
      final climbGrade = creatorResponse?['grade'] ?? 'N/A';
      final creatorId = creatorResponse?['id'];

      final sendsResponse = await Supabase.instance.client
          .from('climbssent')
          .select()
          .eq('climbid', widget.climbId);
      if (!mounted) return;

      final sendsCount = sendsResponse.length;

      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              children: [
                Text(
                  'Climb Info',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Created By:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(displayName),
                  ],
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Grade:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(climbGrade),
                  ],
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'User Sends:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(sendsCount.toString()),
                  ],
                ),
                const Divider(),
                if (creatorId == userId) ...[
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.delete),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    label: const Text('Delete Climb'),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Delete Climb'),
                          content: const Text(
                            'Are you sure you want to delete this climb? This cannot be undone.',
                          ),
                          actions: [
                            TextButton(
                              child: const Text('Cancel'),
                              onPressed: () => Navigator.pop(context, false),
                            ),
                            ElevatedButton(
                              child: const Text('Delete'),
                              onPressed: () => Navigator.pop(context, true),
                            ),
                          ],
                        ),
                      );
                      if (!mounted) return;
                      if (confirm == true) {
                        await Supabase.instance.client
                            .from('climbs')
                            .delete()
                            .eq('climbid', widget.climbId);
                        if (!mounted) return;
                        Navigator.pop(context);
                        Navigator.pop(context);
                      }
                    },
                  ),
                  const Divider(),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    child: const Text('Close'),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Error loading climb info')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageAspectRatio = originalImageWidth / originalImageHeight;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: true,
        title: Text(
          climbName.isEmpty
              ? 'Loading...'
              : climbGrade.isEmpty
              ? climbName
              : '$climbName | $climbGrade',
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.info),
            onPressed: () => _infoForm(context),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final maxHeight = constraints.maxHeight;
          final fontScale = maxWidth / 1500;

          double displayedWidth;
          double displayedHeight;

          if (maxWidth / maxHeight > imageAspectRatio) {
            displayedHeight = maxHeight * 0.9;
            displayedWidth = displayedHeight * imageAspectRatio;
          } else {
            displayedWidth = maxWidth * 0.9;
            displayedHeight = displayedWidth / imageAspectRatio;
          }

          final displayedSize = Size(displayedWidth, displayedHeight);

          return SingleChildScrollView(
            child: Center(
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: InteractiveViewer(
                      panEnabled: true,
                      scaleEnabled: true,
                      minScale: 1.0,
                      maxScale: 5.0,
                      child: Stack(
                        children: [
                          Image.asset(
                            'assets/spray_wall.jpeg',
                            width: displayedWidth,
                            height: displayedHeight,
                            fit: BoxFit.fill,
                          ),
                          CustomPaint(
                            size: displayedSize,
                            painter: _HtmlMapPainter(
                              holdsList,
                              displayedWidth / originalImageWidth,
                              displayedHeight / originalImageHeight,
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
                      final initialGrade =
                          int.tryParse(
                            climbGrade.replaceAll(RegExp(r'[vV]'), ''),
                          ) ??
                          0;
                      _sendForm(context, initialGrade);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Log'),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
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

      final scaledPoints = hold.points
          .map((p) => Offset(p.dx * scaleX, p.dy * scaleY))
          .toList();
      final path = Path()..addPolygon(scaledPoints, true);

      final fillPaint = Paint()
        ..color = switch (hold.selected) {
          1 => Colors.blue.withValues(alpha: 0.5),
          2 => Colors.orange.withValues(alpha: 0.5),
          3 => Colors.green.withValues(alpha: 0.5),
          4 => Colors.purple.withValues(alpha: 0.5),
          _ => Colors.transparent,
        }
        ..style = PaintingStyle.fill;

      final strokePaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);

      final holdLabel = switch (hold.selected) {
        1 => 'Hand',
        2 => 'Foot',
        3 => 'Start',
        4 => 'Finish',
        _ => '',
      };

      if (holdLabel.isNotEmpty) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: holdLabel,
            style: TextStyle(
              color: Colors.white,
              fontSize: 15 * fontScale,
              fontWeight: FontWeight.bold,
              shadows: [
                const Shadow(
                  blurRadius: 3,
                  color: Colors.black,
                  offset: Offset(1, 1),
                ),
              ],
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();

        final centerX =
            scaledPoints.map((p) => p.dx).reduce((a, b) => a + b) /
            scaledPoints.length;
        final centerY =
            scaledPoints.map((p) => p.dy).reduce((a, b) => a + b) /
            scaledPoints.length;
        final center = Offset(centerX, centerY);

        textPainter.paint(
          canvas,
          center - Offset(textPainter.width / 2, textPainter.height / 2),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HtmlMapPainter oldDelegate) => true;
}
