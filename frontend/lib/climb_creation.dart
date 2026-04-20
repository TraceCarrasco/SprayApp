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
  bool _isPrivate = false;

  @override
  void initState() {
    super.initState();
    holdsList = holds.map((h) => HtmlMapHold(h.points)).toList();
  }

  @override
  void dispose() {
    for (final hold in holdsList) {
      hold.selected = 0;
    }
    selectedHolds.clear();
    super.dispose();
  }

  String generateUuid() {
    final uuid = Uuid();
    return uuid.v4();
  }

  bool _hasStartAndFinish() {
    bool hasStart = false;
    bool hasFinish = false;

    for (final hold in selectedHolds) {
      if (hold.selected == 3) hasStart = true;
      if (hold.selected == 4) hasFinish = true;
    }

    return hasStart && hasFinish;
  }

  void _handleTap(TapUpDetails details, Size displayedImageSize) {
    final tapPos = details.localPosition;

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

  void _showInfoDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('How to Set Holds'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Must have at least 1 start and 1 finish hold.\n'),
            Text('1 tap (blue) = hand'),
            Text('2 tap (orange) = foot'),
            Text('3 tap (green) = start'),
            Text('4 tap (purple) = finish'),
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


  Future<void> _insertClimbs(
    String name,
    String grade,
    List<Map<String, dynamic>> holds,
    String climbDescription,
    bool isPrivate,
    bool isDraft,
    bool isSent,
  ) async {
    String climbId = generateUuid();
    final user = Supabase.instance.client.auth.currentUser;
    final userResponse = await Supabase.instance.client.auth.getUser();
    if (!mounted) return;

    final displayName =
        userResponse.user?.userMetadata?['display_name'] ?? 'Unknown';

    final List<Map<String, dynamic>> ascents = isSent
        ? [
            {
              'user_id': user?.id,
              'username': displayName,
              'attempts': null,
              'grade_feel': null,
              'is_flash': false,
              'timestamp': DateTime.now().toIso8601String(),
            }
          ]
        : [];

    try {
      await Supabase.instance.client.from('climbs').insert({
        'climbid': climbId,
        'id': user?.id,
        'name': name,
        'grade': grade,
        'notes': climbDescription.isEmpty ? null : climbDescription,
        'displayname': displayName,
        'holds': holds,
        'private': isPrivate,
        'draft': isDraft,
        'createdat': DateTime.now().toIso8601String(),
        if (isSent) 'ascents': ascents,
        if (isSent) 'sends': 1,
      });
    } catch (e) {
      debugPrint("Error inserting climb: $e");
    }

    // Reset state
    for (final hold in holdsList) {
      hold.selected = 0;
    }
    selectedHolds.clear();
    _isPrivate = false;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final imageAspectRatio = originalImageWidth / originalImageHeight;

    return Scaffold(
appBar: AppBar(
  leading: IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => Navigator.pop(context),
  ),
  title: const Text(''),
  backgroundColor: Colors.transparent,
  elevation: 0,
  actions: [
    IconButton(
      icon: const Icon(Icons.info_outline),
      onPressed: () {
        _showInfoDialog(context);
      },
    ),
  ],
),

      body: LayoutBuilder(
        builder: (context, constraints) {
          final displayedWidth = constraints.maxWidth;
          final displayedHeight = displayedWidth / imageAspectRatio;
          final displayedSize = Size(displayedWidth, displayedHeight);

          return SingleChildScrollView(
            child: Center(
              child: Column(
                children: [
                  SizedBox(height: displayedHeight * .5),
                  InteractiveViewer(
                    panEnabled: true,
                    scaleEnabled: true,
                    minScale: 1.0,
                    maxScale: 5.0,
                    child: GestureDetector(
                      onTapUp: (details) =>
                          _handleTap(details, displayedSize),
                      child: Stack(
                        children: [
                          ColorFiltered(
                            colorFilter: const ColorFilter.matrix([
                              1.0722, -0.429, -0.0432, 0, -25.5,
                              -0.1278, 0.771, -0.0432, 0, -25.5,
                              -0.1278, -0.429, 1.1568, 0, -25.5,
                              0, 0, 0, 1, 0,
                            ]),
                            child: Image.asset(
                              'assets/spray_wall.jpeg',
                              width: displayedWidth,
                              height: displayedHeight,
                              fit: BoxFit.fill,
                              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                                if (wasSynchronouslyLoaded || frame != null) return child;
                                return SizedBox(
                                  width: displayedWidth,
                                  height: displayedHeight,
                                  child: const Center(child: CircularProgressIndicator()),
                                );
                              },
                            ),
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
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      if (!_hasStartAndFinish()) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Select at least one START and one FINISH hold before creating a climb.',
                            ),
                          ),
                        );
                        return;
                      }

                      _openCreateClimbForm(context);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Create Climb'),
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
    bool isPrivate = _isPrivate;
    bool isDraft = false;
    bool isSent = false;

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
                Text(
                  'Create New Climb',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16, width: double.infinity),
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
                        const SizedBox(height: 8),
                        const Text(
                          'Grade',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Slider(
                          value: _sliderValue.toDouble(),
                          min: -1,
                          max: 17,
                          divisions: 18,
                          label: _sliderValue == -1 ? '?' : 'V$_sliderValue',
                          onChanged: (newValue) {
                            setModalState(() {
                              _sliderValue = newValue.round();
                            });
                          },
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Selected Grade: ${_sliderValue == -1 ? '?' : 'V$_sliderValue'}',
                          ),
                        ),
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          title: const Text('Private'),
                          subtitle: const Text(
                            'Only you can see this climb',
                            style: TextStyle(fontSize: 12),
                          ),
                          value: isPrivate,
                          onChanged: (value) {
                            setModalState(() {
                              isPrivate = value ?? false;
                            });
                          },
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                        CheckboxListTile(
                          title: const Text('Sent'),
                          subtitle: const Text(
                            'Mark that you have sent this climb',
                            style: TextStyle(fontSize: 12),
                          ),
                          value: isSent,
                          onChanged: (value) {
                            setModalState(() {
                              isSent = value ?? false;
                            });
                          },
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                        CheckboxListTile(
                          title: const Text('Save as Draft'),
                          subtitle: const Text(
                            'Save without publishing — edit and publish later',
                            style: TextStyle(fontSize: 12),
                          ),
                          value: isDraft,
                          onChanged: (value) {
                            setModalState(() {
                              isDraft = value ?? false;
                            });
                          },
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
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
                        if (!formKey.currentState!.validate()) return;

                        formKey.currentState!.save();
                        climbGrade = _sliderValue == -1 ? '?' : 'V$_sliderValue';

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
                          return;
                        }

                        _insertClimbs(
                          climbName,
                          climbGrade,
                          holdData,
                          climbDescription,
                          isPrivate,
                          isDraft,
                          isSent,
                        );
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16, width: double.infinity),
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
      if (hold.selected == 0) continue;

      final scaledPoints = hold.points
          .map((p) => Offset(p.dx * scaleX, p.dy * scaleY))
          .toList();

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

bool _isPointInPolygon(Offset point, List<Offset> polygon) {
  int intersections = 0;
  for (int i = 0; i < polygon.length; i++) {
    final p1 = polygon[i];
    final p2 = polygon[(i + 1) % polygon.length];

    if ((p1.dy > point.dy) != (p2.dy > point.dy)) {
      final x =
          (p2.dx - p1.dx) * (point.dy - p1.dy) / (p2.dy - p1.dy) + p1.dx;
      if (point.dx < x) intersections++;
    }
  }
  return intersections.isOdd;
}