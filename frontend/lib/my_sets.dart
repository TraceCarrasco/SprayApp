import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'climb_display.dart';
import 'climb_creation.dart';

class MySetsPage extends StatefulWidget {
  const MySetsPage({super.key});

  @override
  State<MySetsPage> createState() => _MySetsPageState();
}

class _MySetsPageState extends State<MySetsPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> myClimbs = [];

  @override
  void initState() {
    super.initState();
    _fetchMyClimbs();
  }

  Future<void> _fetchMyClimbs() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _isLoading = true);

    try {
      final response = await Supabase.instance.client
          .from('climbs')
          .select('climbid, name, grade, id, displayname')
          .eq('id', userId)
          .order('createdat', ascending: false);

      if (!mounted) return;

      setState(() {
        myClimbs = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Error fetching my sets: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
        title: const Text("My Sets"),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Create new climb button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    _fetchMyClimbs(); // refresh on return
                  },
                ),
              ),
            ),

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : myClimbs.isEmpty
                      ? const Center(
                          child: Text("You haven't created any climbs yet."),
                        )
                      : ListView.builder(
                          itemCount: myClimbs.length,
                          itemBuilder: (context, index) {
                            final climb = myClimbs[index];
                            final grade = climb['grade'] ?? '';

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
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                title: Text(
                                  climb['name'] ?? 'Unnamed Climb',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: const Text(
                                  'Set by you',
                                  style: TextStyle(fontSize: 12),
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
