import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'climb_display.dart';
import 'climb_creation.dart';

class ClimbList extends StatefulWidget {
  const ClimbList({super.key});

  @override
  State<ClimbList> createState() => _ClimbListState();
}

enum _SortOption { newest, oldest, mostSends, hardest, easiest }

class _ClimbListState extends State<ClimbList>
    with AutomaticKeepAliveClientMixin {
  String searchQuery = '';
  int minGrade = 0;
  int maxGrade = 16;
  _SortOption _sortOption = _SortOption.mostSends;
  String? _selectedSetter;
  List<String> _setters = [];

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
    _fetchSetters();
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

  Future<void> _fetchSetters() async {
    try {
      final response = await Supabase.instance.client
          .from('climbs')
          .select('displayname');
      if (!mounted) return;
      final names = List<Map<String, dynamic>>.from(response)
          .map((r) => r['displayname']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      setState(() => _setters = names);
    } catch (e) {
      debugPrint('Error fetching setters: $e');
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
      dynamic base = Supabase.instance.client
          .from('climbs')
          .select('climbid, name, grade, id, displayname, private, draft, sends, ascents');

      if (_selectedSetter != null) {
        base = base.eq('displayname', _selectedSetter!);
      }

      final response = await switch (_sortOption) {
        _SortOption.newest =>
          base.order('createdat', ascending: false).range(_offset, _offset + _pageSize - 1),
        _SortOption.oldest =>
          base.order('createdat', ascending: true).range(_offset, _offset + _pageSize - 1),
        _SortOption.mostSends || _SortOption.hardest || _SortOption.easiest =>
          base.order('createdat', ascending: false),
      };

      if (!mounted) return;

      final fetched = List<Map<String, dynamic>>.from(response);
      final isClientSort = _sortOption == _SortOption.hardest ||
          _sortOption == _SortOption.easiest ||
          _sortOption == _SortOption.mostSends;
      setState(() {
        allClimbs.addAll(fetched);
        _offset += fetched.length;
        _hasMore = isClientSort ? false : fetched.length == _pageSize;
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

      // '?' grade (gradeNum == null) always passes the grade range filter
      final gradeMatch =
          gradeNum == null || (gradeNum >= minGrade && gradeNum <= maxGrade);

      return nameMatch && gradeMatch;
    }).toList()
      ..sort((a, b) {
        if (_sortOption == _SortOption.hardest || _sortOption == _SortOption.easiest) {
          final diff = _computeGradeValue(a).compareTo(_computeGradeValue(b));
          return _sortOption == _SortOption.hardest ? -diff : diff;
        }
        if (_sortOption == _SortOption.mostSends) {
          final sendsA = ((a['ascents'] as List<dynamic>?) ?? []).length;
          final sendsB = ((b['ascents'] as List<dynamic>?) ?? []).length;
          return sendsB.compareTo(sendsA);
        }
        return 0;
      });
  }

  int _computeGradeValue(Map<String, dynamic> climb) {
    final grades = ((climb['ascents'] as List<dynamic>?) ?? [])
        .map((a) => a['grade_feel'])
        .whereType<num>()
        .map((g) => g.toInt())
        .toList();
    if (grades.isEmpty) return _extractGradeNumber(climb['grade'] ?? '') ?? 0;
    return (grades.reduce((a, b) => a + b) / grades.length).ceil();
  }

  int? _extractGradeNumber(String grade) {
    final match = RegExp(r'V(\d+)').firstMatch(grade.toUpperCase());
    return match != null ? int.tryParse(match.group(1)!) : null;
  }

  void _showFilterDialog() {
    RangeValues selectedRange =
        RangeValues(minGrade.toDouble(), maxGrade.toDouble());
    _SortOption tempSort = _sortOption;
    String? tempSetter = _selectedSetter;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter & Sort'),
        content: StatefulBuilder(
          builder: (context, setStateDialog) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Grade Range',
                      style: TextStyle(fontWeight: FontWeight.bold)),
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
                  const SizedBox(height: 16),
                  const Text('Sort By',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButton<_SortOption>(
                    value: tempSort,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                        value: _SortOption.newest,
                        child: Text('Newest'),
                      ),
                      DropdownMenuItem(
                        value: _SortOption.oldest,
                        child: Text('Oldest'),
                      ),
                      DropdownMenuItem(
                        value: _SortOption.mostSends,
                        child: Text('Most Sends'),
                      ),
                      DropdownMenuItem(
                        value: _SortOption.hardest,
                        child: Text('Hardest'),
                      ),
                      DropdownMenuItem(
                        value: _SortOption.easiest,
                        child: Text('Easiest'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setStateDialog(() => tempSort = value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('Set By',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Autocomplete<String>(
                    initialValue:
                        TextEditingValue(text: tempSetter ?? ''),
                    optionsBuilder: (TextEditingValue value) {
                      if (value.text.isEmpty) return _setters;
                      return _setters.where((name) => name
                          .toLowerCase()
                          .contains(value.text.toLowerCase()));
                    },
                    onSelected: (String selection) {
                      setStateDialog(() => tempSetter = selection);
                    },
                    fieldViewBuilder:
                        (context, controller, focusNode, onSubmitted) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          hintText: 'All Setters',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.search),
                          isDense: true,
                        ),
                        onChanged: (v) {
                          if (v.isEmpty) {
                            setStateDialog(() => tempSetter = null);
                          }
                        },
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              final needsRefetch = _sortOption != _SortOption.mostSends ||
                  _selectedSetter != null;
              setState(() {
                minGrade = 0;
                maxGrade = 16;
                _sortOption = _SortOption.mostSends;
                _selectedSetter = null;
              });
              Navigator.pop(context);
              if (needsRefetch) _fetchClimbs();
            },
            child: const Text('Reset'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final newMin = selectedRange.start.round();
              final newMax = selectedRange.end.round();
              final needsRefetch = tempSort != _sortOption ||
                  tempSetter != _selectedSetter;
              setState(() {
                minGrade = newMin;
                maxGrade = newMax;
                _sortOption = tempSort;
                _selectedSetter = tempSetter;
              });
              Navigator.pop(context);
              if (needsRefetch) _fetchClimbs();
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
                            final isPrivate = climb['private'] == true;
                            final grades = ((climb['ascents'] as List<dynamic>?) ?? [])
                                .map((a) => a['grade_feel'])
                                .whereType<num>()
                                .map((g) => g.toInt())
                                .toList();
                            final displayGrade = grades.isEmpty
                                ? (climb['grade'] ?? '?')
                                : 'V${(grades.reduce((a, b) => a + b) / grades.length).ceil()}';

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: () {
                                    final match = RegExp(r'V(\d+)')
                                        .firstMatch(displayGrade.toUpperCase());
                                    final n = match != null
                                        ? int.tryParse(match.group(1)!) ?? 0
                                        : 0;
                                    if (n >= 9) return Colors.red;
                                    if (n >= 7) return Colors.orange;
                                    if (n >= 4) return Colors.blue;
                                    if (n >= 3) return Colors.green;
                                    return Colors.yellow.shade700;
                                  }(),
                                  child: Text(displayGrade),
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
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        'Total sends: ${climb['sends'] ?? 0}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: const Icon(
                                  Icons.arrow_forward_ios,
                                  size: 16,
                                ),
                                onTap: () async {
                                  final ids = filteredClimbs
                                      .map((c) => c['climbid'].toString())
                                      .toList();
                                  final idx = ids.indexOf(climb['climbid'].toString());
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ClimbDisplay(
                                        climbId: climb['climbid'],
                                        climbIds: ids,
                                        currentIndex: idx < 0 ? 0 : idx,
                                      ),
                                    ),
                                  );
                                  _fetchClimbs();
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