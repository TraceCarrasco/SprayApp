import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'holds.dart';

const double originalImageWidth = 5712;
const double originalImageHeight = 4284;

class ClimbUpdatePage extends StatefulWidget {
  final String climbId;
  final bool isDraft;

  const ClimbUpdatePage({
    super.key,
    required this.climbId,
    this.isDraft = false,
  });

  @override
  State<ClimbUpdatePage> createState() => _ClimbUpdatePageState();
}

class _ClimbUpdatePageState extends State<ClimbUpdatePage> {
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
        gradeValue = climbGrade == '?'
            ? -1
            : int.tryParse(climbGrade.replaceAll(RegExp(r'[vV]'), '')) ?? 0;

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

  Future<void> _save({bool publish = false}) async {
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
      if (widget.isDraft) update['draft'] = publish ? false : true;

      await Supabase.instance.client
          .from('climbs')
          .update(update)
          .eq('climbid', widget.climbId);

      if (mounted) {
        final message = widget.isDraft
            ? (publish ? 'Climb published!' : 'Draft saved!')
            : 'Climb updated successfully!';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.pop(context, widget.isDraft ? (publish ? 'published' : 'saved') : true);
      }
    } catch (e) {
      debugPrint('Error saving climb: $e');
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

  void _openForm(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    String updatedName = climbName;
    String updatedNotes = notes;
    int updatedGradeValue = gradeValue;
    bool updatedPrivate = isPrivate;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Form(
            key: formKey,
            child: Wrap(
              children: [
                Text(
                  widget.isDraft ? 'Edit Draft' : 'Update Climb',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 16, width: double.infinity),
                TextFormField(
                  initialValue: climbName,
                  decoration: const InputDecoration(labelText: 'Climb Name'),
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Enter a name' : null,
                  onSaved: (v) => updatedName = v ?? '',
                ),
                TextFormField(
                  initialValue: notes,
                  decoration: const InputDecoration(labelText: 'Description'),
                  maxLines: 1,
                  onSaved: (v) => updatedNotes = v ?? '',
                ),
                StatefulBuilder(
                  builder: (ctx, setModalState) {
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
                          min: -1,
                          max: 17,
                          divisions: 18,
                          label: updatedGradeValue == -1
                              ? '?'
                              : 'V$updatedGradeValue',
                          onChanged: (v) => setModalState(
                              () => updatedGradeValue = v.round()),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Selected Grade: ${updatedGradeValue == -1 ? '?' : 'V$updatedGradeValue'}',
                          ),
                        ),
                        const SizedBox(height: 4),
                        CheckboxListTile(
                          title: const Text('Private'),
                          subtitle: const Text(
                            'Only you can see this climb',
                            style: TextStyle(fontSize: 12),
                          ),
                          value: updatedPrivate,
                          onChanged: (v) => setModalState(
                              () => updatedPrivate = v ?? false),
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
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    if (widget.isDraft) ...[
                      OutlinedButton(
                        onPressed: () {
                          if (!formKey.currentState!.validate()) return;
                          formKey.currentState!.save();
                          climbName = updatedName;
                          notes = updatedNotes;
                          climbGrade = updatedGradeValue == -1 ? '?' : 'V$updatedGradeValue';
                          gradeValue = updatedGradeValue;
                          isPrivate = updatedPrivate;
                          Navigator.pop(ctx);
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
                          climbGrade = updatedGradeValue == -1 ? '?' : 'V$updatedGradeValue';
                          gradeValue = updatedGradeValue;
                          isPrivate = updatedPrivate;
                          Navigator.pop(ctx);
                          _save(publish: true);
                        },
                        child: const Text('Publish'),
                      ),
                    ] else
                      ElevatedButton(
                        onPressed: () {
                          if (!formKey.currentState!.validate()) return;
                          formKey.currentState!.save();
                          climbName = updatedName;
                          notes = updatedNotes;
                          climbGrade = updatedGradeValue == -1 ? '?' : 'V$updatedGradeValue';
                          gradeValue = updatedGradeValue;
                          isPrivate = updatedPrivate;
                          Navigator.pop(ctx);
                          _save();
                        },
                        child: const Text('Save'),
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
    final imageAspectRatio = originalImageWidth / originalImageHeight;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.isDraft
            ? (climbName.isEmpty ? 'Edit Draft' : climbName)
            : 'Update Climb'),
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
                                      painter: _HoldPainter(
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
                                _openForm(context);
                              },
                              icon: Icon(widget.isDraft
                                  ? Icons.arrow_forward
                                  : Icons.save),
                              label: Text(
                                  widget.isDraft ? 'Next' : 'Save Changes'),
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

class _HoldPainter extends CustomPainter {
  final List<HtmlMapHold> holds;
  final double scaleX;
  final double scaleY;
  final double fontScale;

  _HoldPainter(this.holds, this.scaleX, this.scaleY, this.fontScale);

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
  bool shouldRepaint(covariant _HoldPainter oldDelegate) => true;
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
