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
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  static const int _pageSize = 50;

  List<Map<String, dynamic>> allClimbs = [];

  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _fetchClimbs();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      if (!_isLoadingMore && _hasMore) {
        _fetchClimbs(loadMore: true);
      }
    }
  }

  Future<void> _fetchClimbs({bool loadMore = false}) async {
    if (loadMore) {
      if (_isLoadingMore || !_hasMore) return;
      setState(() => _isLoadingMore = true);
    } else {
      setState(() {
        _isLoading = true;
        _offset = 0;
        allClimbs = [];
      });
    }

    try {
      final response = await Supabase.instance.client
          .from('climbs')
          .select('climbid, name, grade, id, displayname, private, draft')
          .order('createdat', ascending: false)
          .range(_offset, _offset + _pageSize - 1);

      if (!mounted) return;

      final fetched = List<Map<String, dynamic>>.from(response);
      setState(() {
        allClimbs.addAll(fetched);
        _offset += fetched.length;
        _hasMore = fetched.length == _pageSize;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      debugPrint('❌ Error fetching climbs: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  List<Map<String, dynamic>> get filteredClimbs {
    final userId = Supabase.instance.client.auth.currentUser?.id;

    return allClimbs.where((climb) {
      final isPrivate = climb['private'] == true;
      final isDraft = climb['draft'] == true;
      final isCreator = userId != null && climb['id'] == userId;

      if (isDraft) return false;
      if (isPrivate && !isCreator) return false;

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
                    _fetchClimbs(); // reset + reload from top
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
                          controller: _scrollController,
                          itemCount: climbs.length + (_isLoadingMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == climbs.length) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
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