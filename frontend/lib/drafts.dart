import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'draft_edit.dart';

class DraftsPage extends StatefulWidget {
  const DraftsPage({super.key});

  @override
  State<DraftsPage> createState() => _DraftsPageState();
}

class _DraftsPageState extends State<DraftsPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> drafts = [];

  @override
  void initState() {
    super.initState();
    _fetchDrafts();
  }

  Future<void> _fetchDrafts() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _isLoading = true);

    try {
      final response = await Supabase.instance.client
          .from('climbs')
          .select('climbid, name, grade, createdat')
          .eq('id', userId)
          .eq('draft', true)
          .order('createdat', ascending: false);

      if (!mounted) return;

      setState(() {
        drafts = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching drafts: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int _extractGradeNumber(String grade) {
    final match = RegExp(r'V(\d+)').firstMatch(grade.toUpperCase());
    return match != null ? int.tryParse(match.group(1)!) ?? 0 : 0;
  }

  Color _gradeColor(String grade) {
    final gradeNum = _extractGradeNumber(grade);
    if (gradeNum <= 4) return Colors.green;
    if (gradeNum <= 8) return Colors.blue;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drafts'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : drafts.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.edit_note, size: 48, color: Colors.grey),
                        SizedBox(height: 12),
                        Text(
                          'No drafts yet.',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: drafts.length,
                    itemBuilder: (context, index) {
                      final draft = drafts[index];
                      final grade = draft['grade'] ?? '';

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _gradeColor(grade),
                            child: Text(
                              grade.isNotEmpty ? grade : '?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          title: Text(
                            draft['name'] ?? 'Unnamed Draft',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Row(
                            children: [
                              Icon(
                                Icons.edit_note,
                                size: 14,
                                color: Colors.orange.shade700,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Draft',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange.shade700,
                                ),
                              ),
                            ],
                          ),
                          trailing: const Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                          ),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => DraftEditPage(
                                  climbId: draft['climbid'],
                                ),
                              ),
                            );
                            _fetchDrafts();
                          },
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
