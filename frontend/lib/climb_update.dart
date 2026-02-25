import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'holds.dart';

const double originalImageWidth = 5712;
const double originalImageHeight = 4284;

class ClimbUpdatePage extends StatefulWidget {
  final String climbId;

  const ClimbUpdatePage({super.key, required this.climbId});

  @override
  State<ClimbUpdatePage> createState() => _ClimbUpdatePageState();
}

class _ClimbUpdatePageState extends State<ClimbUpdatePage> {
  late List<HtmlMapHold> holdsList;
  List<HtmlMapHold> selectedHolds = [];
  bool loading = true;
  String? error;

  // Climb data
  String climbName = '';
  String climbGrade = '';
  String notes = '';
  int gradeValue = 0;

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

  Future<void> _fetchClimbData() async {
    try {
      final climbResponse = await Supabase.instance.client
          .from('climbs')
          .select('name, grade, holds, notes')
          .eq('climbid', widget.climbId)
          .maybeSingle();

      if (climbResponse != null) {
        climbName = climbResponse['name'] ?? '';
        climbGrade = climbResponse['grade'] ?? '';
        notes = climbResponse['notes'] ?? '';

        // Extract grade value (remove 'V' prefix)
        gradeValue = int.tryParse(climbGrade.replaceAll(RegExp(r'[vV]'), '')) ?? 0;

        // Parse and restore holds
        final holdsJson = climbResponse['holds'];
        if (holdsJson != null) {
          final List<dynamic> holdsData = holdsJson is List ? holdsJson : [];

          for (final holdData in holdsData) {
            final int arrayIndex = holdData['array_index'] ?? -1;
            final int holdState = holdData['holdstate'] ?? 0;

            if (arrayIndex >= 0 && arrayIndex < holdsList.length) {
              holdsList[arrayIndex].selected = holdState;
              selectedHolds.add(holdsList[arrayIndex]);
            }
          }
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

  Future<void> _updateClimb(
    String name,
    String grade,
    List<Map<String, dynamic>> holds,
    String climbDescription,
  ) async {
    try {
      await Supabase.instance.client.from('climbs').update({
        'name': name,
        'grade': grade,
        'notes': climbDescription.isEmpty ? null : climbDescription,
        'holds': holds,
      }).eq('climbid', widget.climbId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Climb updated successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      debugPrint("Error updating climb: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating climb: $e'),
            backgroundColor: Colors.red,
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Update Climb'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text(error!))
              : LayoutBuilder(
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
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () {
                                if (!_hasStartAndFinish()) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Select at least one START and one FINISH hold.',
                                      ),
                                    ),
                                  );
                                  return;
                                }

                                _openUpdateClimbForm(context);
                              },
                              icon: const Icon(Icons.save),
                              label: const Text('Save Changes'),
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

  void _openUpdateClimbForm(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    String updatedName = climbName;
    String updatedDescription = notes;
    int updatedGradeValue = gradeValue;

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
                  'Update Climb',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                TextFormField(
                  initialValue: climbName,
                  decoration: const InputDecoration(labelText: 'Climb Name'),
                  validator: (value) =>
                      value == null || value.isEmpty ? 'Enter a name' : null,
                  onSaved: (value) => updatedName = value ?? '',
                ),
                TextFormField(
                  initialValue: notes,
                  decoration: const InputDecoration(labelText: 'Description'),
                  maxLines: 1,
                  onSaved: (value) => updatedDescription = value ?? '',
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
                          value: updatedGradeValue.toDouble(),
                          min: 0,
                          max: 17,
                          divisions: 17,
                          label: 'V$updatedGradeValue',
                          onChanged: (newValue) {
                            setModalState(() {
                              updatedGradeValue = newValue.round();
                            });
                          },
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text('Selected Grade: V$updatedGradeValue'),
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
                        final updatedGrade = 'V$updatedGradeValue';

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

                        _updateClimb(
                          updatedName,
                          updatedGrade,
                          holdData,
                          updatedDescription,
                        );
                        Navigator.pop(context);
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
      if (hold.selected == 0) continue;

      final scaledPoints = hold.points
          .map((p) => Offset(p.dx * scaleX, p.dy * scaleY))
          .toList();

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