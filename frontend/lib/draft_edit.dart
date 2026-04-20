import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'holds.dart';

const double _originalImageWidth = 5712;
const double _originalImageHeight = 4284;

class DraftEditPage extends StatefulWidget {
  final String climbId;

  const DraftEditPage({super.key, required this.climbId});

  @override
  State<DraftEditPage> createState() => _DraftEditPageState();
}

class _DraftEditPageState extends State<DraftEditPage> {
  late List<HtmlMapHold> holdsList;
  List<HtmlMapHold> selectedHolds = [];
  bool loading = true;
  String? error;

  String climbName = '';
  String climbGrade = '';
  String notes = '';
  bool isPrivate = false;
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
      final response = await Supabase.instance.client
          .from('climbs')
          .select('name, grade, holds, notes, private')
          .eq('climbid', widget.climbId)
          .maybeSingle();

      if (response != null) {
        climbName = response['name'] ?? '';
        climbGrade = response['grade'] ?? '';
        notes = response['notes'] ?? '';
        isPrivate = response['private'] == true;
        gradeValue =
            int.tryParse(climbGrade.replaceAll(RegExp(r'[vV]'), '')) ?? 0;

        final holdsJson = response['holds'];
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

      setState(() => loading = false);
    } catch (e) {
      setState(() {
        error = 'Error fetching draft: $e';
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
      tapPos.dx / displayedImageSize.width * _originalImageWidth,
      tapPos.dy / displayedImageSize.height * _originalImageHeight,
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

  Future<void> _save({required bool publish}) async {
    final List<Map<String, dynamic>> holdData = [];
    for (int i = 0; i < holdsList.length; i++) {
      if (selectedHolds.contains(holdsList[i])) {
        holdData.add({
          'array_index': i,
          'holdstate': holdsList[i].selected,
        });
      }
    }

    try {
      final Map<String, dynamic> update = {
        'name': climbName,
        'grade': climbGrade,
        'notes': notes.isEmpty ? null : notes,
        'holds': holdData,
        'private': isPrivate,
      };
      if (publish) update['draft'] = false;

      await Supabase.instance.client
          .from('climbs')
          .update(update)
          .eq('climbid', widget.climbId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(publish ? 'Climb published!' : 'Draft saved!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.pop(context, publish ? 'published' : 'saved');
      }
    } catch (e) {
      debugPrint('Error saving draft: $e');
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

  void _openDraftForm(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    String updatedName = climbName;
    String updatedNotes = notes;
    int updatedGradeValue = gradeValue;
    bool updatedPrivate = isPrivate;

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
                  'Edit Draft',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16, width: double.infinity),
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
                  onSaved: (value) => updatedNotes = value ?? '',
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
                          value: updatedGradeValue.toDouble(),
                          min: 0,
                          max: 17,
                          divisions: 17,
                          label: 'V$updatedGradeValue',
                          onChanged: (v) => setModalState(
                              () => updatedGradeValue = v.round()),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text('Selected Grade: V$updatedGradeValue'),
                        ),
                        const SizedBox(height: 4),
                        CheckboxListTile(
                          title: const Text('Private'),
                          subtitle: const Text(
                            'Only you can see this climb',
                            style: TextStyle(fontSize: 12),
                          ),
                          value: updatedPrivate,
                          onChanged: (v) =>
                              setModalState(() => updatedPrivate = v ?? false),
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
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () {
                        if (!formKey.currentState!.validate()) return;
                        formKey.currentState!.save();
                        climbName = updatedName;
                        notes = updatedNotes;
                        climbGrade = 'V$updatedGradeValue';
                        gradeValue = updatedGradeValue;
                        isPrivate = updatedPrivate;
                        Navigator.pop(context);
                        _save(publish: false);
                      },
                      child: const Text('Save Draft'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        if (!formKey.currentState!.validate()) return;
                        formKey.currentState!.save();
                        climbName = updatedName;
                        notes = updatedNotes;
                        climbGrade = 'V$updatedGradeValue';
                        gradeValue = updatedGradeValue;
                        isPrivate = updatedPrivate;
                        Navigator.pop(context);
                        _save(publish: true);
                      },
                      child: const Text('Publish'),
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

  @override
  Widget build(BuildContext context) {
    final imageAspectRatio = _originalImageWidth / _originalImageHeight;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(climbName.isEmpty ? 'Edit Draft' : climbName),
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
                                      ),
                                    ),
                                    CustomPaint(
                                      size: displayedSize,
                                      painter: _DraftHoldPainter(
                                        holdsList,
                                        displayedWidth / _originalImageWidth,
                                        displayedHeight / _originalImageHeight,
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
                                _openDraftForm(context);
                              },
                              icon: const Icon(Icons.arrow_forward),
                              label: const Text('Next'),
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
}

class _DraftHoldPainter extends CustomPainter {
  final List<HtmlMapHold> holds;
  final double scaleX;
  final double scaleY;
  final double fontScale;

  _DraftHoldPainter(this.holds, this.scaleX, this.scaleY, this.fontScale);

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
  bool shouldRepaint(covariant _DraftHoldPainter oldDelegate) => true;
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
