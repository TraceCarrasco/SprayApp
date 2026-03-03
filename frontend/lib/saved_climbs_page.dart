import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'climb_display.dart';

class SavedClimbsPage extends StatefulWidget {
  const SavedClimbsPage({super.key});

  @override
  State<SavedClimbsPage> createState() => _SavedClimbsPageState();
}

class _SavedClimbsPageState extends State<SavedClimbsPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _savedClimbs = [];

  @override
  void initState() {
    super.initState();
    _fetchSaved();
  }

  Future<void> _fetchSaved() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _isLoading = true);

    try {
      final response = await Supabase.instance.client
          .from('saved_climbs')
          .select('climbid, saved_at, climbs(name, grade, displayname)')
          .eq('user_id', userId)
          .order('saved_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _savedClimbs = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching saved climbs: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _gradeColor(String grade) {
    final match = RegExp(r'V(\d+)').firstMatch(grade.toUpperCase());
    final n = match != null ? int.tryParse(match.group(1)!) ?? 0 : 0;
    if (n >= 9) return Colors.red;
    if (n >= 7) return Colors.orange;
    if (n >= 4) return Colors.blue;
    if (n >= 3) return Colors.green;
    return Colors.yellow.shade700;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Climbs'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _savedClimbs.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bookmark_outline,
                            size: 48, color: Colors.grey),
                        SizedBox(height: 12),
                        Text(
                          'No saved climbs yet.',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _savedClimbs.length,
                    itemBuilder: (context, index) {
                      final row = _savedClimbs[index];
                      final climb =
                          row['climbs'] as Map<String, dynamic>? ?? {};
                      final grade = climb['grade'] ?? '';
                      final name = climb['name'] ?? 'Unnamed Climb';
                      final setBy = climb['displayname'] ?? '';

                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _gradeColor(grade),
                            child: Text(
                              grade.isNotEmpty ? grade : '?',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11),
                            ),
                          ),
                          title: Text(
                            name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: setBy.isNotEmpty
                              ? Text(
                                  'Set by: $setBy',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600),
                                )
                              : null,
                          trailing: const Icon(Icons.arrow_forward_ios,
                              size: 16),
                          onTap: () async {
                            final ids = _savedClimbs
                                .map((c) => c['climbid'].toString())
                                .toList();
                            final idx = ids.indexOf(row['climbid'].toString());
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ClimbDisplay(
                                  climbId: row['climbid'],
                                  climbIds: ids,
                                  currentIndex: idx < 0 ? 0 : idx,
                                ),
                              ),
                            );
                            _fetchSaved();
                          },
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
