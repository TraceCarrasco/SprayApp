import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'climb_display.dart';
import 'climb_creation.dart';

class ClimbList extends StatefulWidget {
  const ClimbList({super.key});

  @override
  State<ClimbList> createState() => _ClimbListState();
}

class _ClimbListState extends State<ClimbList>
    with AutomaticKeepAliveClientMixin {
  String searchQuery = '';
  int minGrade = 0;
  int maxGrade = 16;
  bool onlyMine = false;

  bool _isLoading = true;

  List<Map<String, dynamic>> allClimbs = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchClimbs();
  }

  Future<void> _fetchClimbs() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await Supabase.instance.client
          .from('climbs')
          .select('climbid, name, grade, id, displayname, private'); // Added 'private'

      if (!mounted) return;

      setState(() {
        allClimbs = List<Map<String, dynamic>>.from(response.reversed);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Error fetching climbs: $e');

      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get filteredClimbs {
    final userId = Supabase.instance.client.auth.currentUser?.id;

    return allClimbs.where((climb) {
      // Check if climb is private - only show if current user is the creator
      final isPrivate = climb['private'] == true;
      final isCreator = userId != null && climb['id'] == userId;
      
      // If climb is private and user is not the creator, filter it out
      if (isPrivate && !isCreator) {
        return false;
      }

      final nameMatch = climb['name']
          .toString()
          .toLowerCase()
          .contains(searchQuery.toLowerCase());

      final gradeStr = climb['grade'] ?? '';
      final gradeNum = _extractGradeNumber(gradeStr);

      final matchesMine = !onlyMine || isCreator;

      return nameMatch &&
          gradeNum != null &&
          gradeNum >= minGrade &&
          gradeNum <= maxGrade &&
          matchesMine;
    }).toList();
  }

  int? _extractGradeNumber(String grade) {
    final match = RegExp(r'V(\d+)').firstMatch(grade.toUpperCase());
    return match != null ? int.tryParse(match.group(1)!) : null;
  }

  void _showFilterDialog() {
    RangeValues selectedRange =
        RangeValues(minGrade.toDouble(), maxGrade.toDouble());
    bool tempOnlyMine = onlyMine;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter by Grade'),
        content: StatefulBuilder(
          builder: (context, setStateDialog) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RangeSlider(
                  min: 0,
                  max: 16,
                  divisions: 16,
                  labels: RangeLabels(
                    'V${selectedRange.start.round()}',
                    'V${selectedRange.end.round()}',
                  ),
                  values: selectedRange,
                  onChanged: (newRange) {
                    setStateDialog(() {
                      selectedRange = newRange;
                    });
                  },
                ),
                Text(
                  'From V${selectedRange.start.round()} to V${selectedRange.end.round()}',
                ),
                const SizedBox(height: 10),
                CheckboxListTile(
                  title: const Text('Set By Me'),
                  value: tempOnlyMine,
                  onChanged: (value) {
                    setStateDialog(() {
                      tempOnlyMine = value ?? false;
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                minGrade = selectedRange.start.round();
                maxGrade = selectedRange.end.round();
                onlyMine = tempOnlyMine;
              });
              Navigator.pop(context);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final climbs = filteredClimbs;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Search climbs',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) {
                        setState(() {
                          searchQuery = value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.filter_list),
                    tooltip: 'Filter by Grade',
                    onPressed: _showFilterDialog,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Create New Climb'),
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ClimbsPage(),
                      ),
                    );
                    _fetchClimbs();
                  },
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : climbs.isEmpty
                      ? const Center(child: Text('No climbs found.'))
                      : ListView.builder(
                          itemCount: climbs.length,
                          itemBuilder: (context, index) {
                            final climb = climbs[index];
                            final isPrivate = climb['private'] == true; // For UI indicator

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: () {
                                    final gradeStr = climb['grade'] ?? '';
                                    final match = RegExp(r'V(\d+)')
                                        .firstMatch(gradeStr.toUpperCase());
                                    final gradeNum = match != null
                                        ? int.tryParse(match.group(1)!) ?? 0
                                        : 0;

                                    if (gradeNum <= 4) return Colors.green;
                                    if (gradeNum <= 8) return Colors.blue;
                                    return Colors.red;
                                  }(),
                                  child: Text(climb['grade'] ?? '?'),
                                ),
                                title: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            climb['name'] ?? 'Unnamed Climb',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        // Optional: Show lock icon for private climbs
                                        if (isPrivate) ...[
                                          const SizedBox(width: 4),
                                          Icon(
                                            Icons.lock,
                                            size: 14,
                                            color: Colors.grey.shade600,
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (climb['displayname'] != null &&
                                        climb['displayname']
                                            .toString()
                                            .isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          'Set by: ${climb['displayname']}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: const Icon(
                                  Icons.arrow_forward_ios,
                                  size: 16,
                                ),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ClimbDisplay(
                                        climbId: climb['climbid'],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}