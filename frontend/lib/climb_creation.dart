import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'holds.dart';
import 'package:uuid/uuid.dart';

const double originalImageWidth = 5712;
const double originalImageHeight = 4284;

class ClimbsPage extends StatefulWidget {
  const ClimbsPage({super.key});

  @override
  State<ClimbsPage> createState() => _ClimbsPageState();
}

class _ClimbsPageState extends State<ClimbsPage> {
  late List<HtmlMapHold> holdsList;
  int _sliderValue = 0;
  List<HtmlMapHold> selectedHolds = [];

  @override
  void initState() {
    super.initState();
    holdsList = holds;
  }

  String generateUuid() {
    final uuid = Uuid();
    return uuid.v4();
  }

  void _handleTap(TapUpDetails details, Size displayedImageSize) {
    final tapPos = details.localPosition;

    // Convert tapPos (on the zoomed/panned widget) to original image coordinates
    // Because InteractiveViewer scales and translates the entire child,
    // details.localPosition is relative to the widget inside InteractiveViewer.
    // So we just scale accordingly:

    final scaledTapPos = Offset(
      tapPos.dx / displayedImageSize.width * originalImageWidth,
      tapPos.dy / displayedImageSize.height * originalImageHeight,
    );

    setState(() {
      for (final hold in holdsList) {
        if (_isPointInPolygon(scaledTapPos, hold.points)) {
          hold.selected = (hold.selected + 1) % 5;
          if (hold.selected == 0) {
            selectedHolds.remove(hold);
          } else if (!selectedHolds.contains(hold)) {
            selectedHolds.add(hold);
          }

          break;
        }
      }
    });
  }

  Future<void> _insertClimbs(
    String name,
    String grade,
    List<Map<String, dynamic>> holds,
    String climbDescription,
  ) async {
    String climbId = generateUuid();
    final userI = Supabase.instance.client.auth.currentUser;
    final userResponse = await Supabase.instance.client.auth.getUser();
    if (!mounted) return;

    final displayName =
        userResponse.user?.userMetadata?['display_name'] ?? 'Unknown';

    try {
      await Supabase.instance.client.from('climbs').insert({
        'climbid': climbId,
        'id': userI?.id, // make sure to get the user's id string
        'name': name,
        'grade': grade,
        'notes': climbDescription.isEmpty ? null : climbDescription,
        'displayname': displayName,
      });
    } catch (e) {
      print("Error inserting climbs {$e}");
    }

    final List<Map<String, dynamic>> holdsToInsert = holds.map((hold) {
      return {
        'climbid': climbId,
        'array_index': hold['array_index'],
        'holdstate': hold['holdstate'],
      };
    }).toList();

    // Insert holds
    try {
      await Supabase.instance.client.from('climbholds').insert(holdsToInsert);
    } catch (e) {
      print("Error inserting holds: {$e}");
    }

    print("Succesfully added climb + holds");

    for (final hold in holdsList) {
      hold.selected = 0;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Calculate aspect ratio of the original image
    final imageAspectRatio = originalImageWidth / originalImageHeight;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final maxHeight = constraints.maxHeight;

          // Calculate image size preserving aspect ratio, and scale to 75%
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
                  const SizedBox(height: 100), // ✅ Top padding
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: InteractiveViewer(
                      panEnabled: true,
                      scaleEnabled: true,
                      minScale: 1.0,
                      maxScale: 5.0,
                      child: GestureDetector(
                        onTapUp: (details) =>
                            _handleTap(details, displayedSize),
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
                                constraints.maxWidth / 1500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _openCreateClimbForm(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add a Climb'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
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

  void _openCreateClimbForm(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    String climbName = '';
    String climbDescription = '';
    String climbGrade = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // for keyboard to push sheet up
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
                Text(
                  'Create New Climb',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Climb Name'),
                  validator: (value) =>
                      value == null || value.isEmpty ? 'Enter a name' : null,
                  onSaved: (value) => climbName = value ?? '',
                ),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Description'),
                  maxLines: 1,
                  onSaved: (value) => climbDescription = value ?? '',
                ),
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
                          label: 'v$_sliderValue',
                          onChanged: (newValue) {
                            setModalState(() {
                              _sliderValue = newValue.round();
                            });
                          },
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text('Selected Grade: v$_sliderValue'),
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
                      onPressed: () {
                        if (formKey.currentState!.validate()) {
                          formKey.currentState!.save();
                          climbGrade = 'V$_sliderValue';

                          final List<Map<String, dynamic>> holdData = [];
                          bool hasStart = false;
                          bool hasFinish = false;

                          for (int i = 0; i < holdsList.length; i++) {
                            if (selectedHolds.contains(holdsList[i])) {
                              if (holdsList[i].selected == 3) hasStart = true;
                              if (holdsList[i].selected == 4) hasFinish = true;

                              holdData.add({
                                'array_index': i,
                                'holdstate': holdsList[i].selected,
                              });
                            }
                          }

                          if (!hasStart || !hasFinish) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please select at least one START and one FINISH hold.',
                                ),
                              ),
                            );
                            return; // Don’t insert
                          }
                          _insertClimbs(
                            climbName,
                            climbGrade,
                            holdData,
                            climbDescription,
                          );
                          Navigator.pop(context);
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
      if (hold.selected == 0) continue; // Skip unselected

      final scaledPoints = hold.points
          .map((p) => Offset(p.dx * scaleX, p.dy * scaleY))
          .toList();

      final path = Path()..addPolygon(scaledPoints, true);

      final fillPaint = Paint()
        ..color = switch (hold.selected) {
          1 => Colors.blue.withValues(alpha: 0.5), // Hand
          2 => Colors.orange.withValues(alpha: 0.5), // Foot
          3 => Colors.green.withValues(alpha: 0.5), // Start
          4 => Colors.purple.withValues(alpha: 0.5), // Finish
          _ => Colors.transparent,
        }
        ..style = PaintingStyle.fill;

      final strokePaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      // Draw the polygon
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);

      // Determine hold label
      final holdLabel = switch (hold.selected) {
        1 => 'Hand',
        2 => 'Foot',
        3 => 'Start',
        4 => 'Finish',
        _ => '',
      };

      // Draw label text in the center of the hold
      if (holdLabel.isNotEmpty) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: holdLabel,
            style: TextStyle(
              color: Colors.white,
              fontSize: 15 * fontScale,
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(
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

        // Find center of polygon to place text
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

// Ray casting algorithm to check if a point is inside a polygon
bool _isPointInPolygon(Offset point, List<Offset> polygon) {
  int intersections = 0;
  for (int i = 0; i < polygon.length; i++) {
    final p1 = polygon[i];
    final p2 = polygon[(i + 1) % polygon.length];

    if ((p1.dy > point.dy) != (p2.dy > point.dy)) {
      final x = (p2.dx - p1.dx) * (point.dy - p1.dy) / (p2.dy - p1.dy) + p1.dx;
      if (point.dx < x) {
        intersections++;
      }
    }
  }
  return (intersections % 2) == 1;
}
