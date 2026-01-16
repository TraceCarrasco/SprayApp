import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LogbookPage extends StatefulWidget {
  const LogbookPage({super.key});

  @override
  State<LogbookPage> createState() => _LogbookPageState();
}

class _LogbookPageState extends State<LogbookPage> {
  List<Map<String, dynamic>> sendLogs = [];
  bool loading = true;

  int totalSends = 0;
  int hardestSendGrade = 0;
  int hardestFlashGrade = 0;

  @override
  void initState() {
    super.initState();
    _fetchUserLogbook();
  }

  /// Converts "V8" -> 8 safely
  int _parseGrade(String? grade) {
    if (grade == null) return 0;
    return int.tryParse(
          grade.toUpperCase().replaceAll('V', ''),
        ) ??
        0;
  }

  Future<void> _fetchUserLogbook() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final response = await Supabase.instance.client
          .from('climbs')
          .select('name, grade, ascents')
          .not('ascents', 'is', null);

      final List<Map<String, dynamic>> logs = [];

      int maxSend = 0;
      int maxFlash = 0;

      for (final climb in response) {
        final ascents = climb['ascents'] as List<dynamic>? ?? [];
        final gradeStr = climb['grade'] as String?;
        final gradeNum = _parseGrade(gradeStr);

        for (final ascent in ascents) {
          if (ascent['user_id'] != user.id) continue;

          final isFlash = ascent['is_flash'] ?? false;

          logs.add({
            'climb_name': climb['name'] ?? 'Unnamed',
            'grade': gradeStr ?? '',
            'grade_num': gradeNum,
            'is_flash': isFlash,
            'timestamp': ascent['timestamp'],
          });

          if (gradeNum > maxSend) maxSend = gradeNum;
          if (isFlash && gradeNum > maxFlash) {
            maxFlash = gradeNum;
          }
        }
      }

      // Newest first
      logs.sort((a, b) {
        final aTime = a['timestamp'] ?? '';
        final bTime = b['timestamp'] ?? '';
        return bTime.compareTo(aTime);
      });

      if (!mounted) return;

      setState(() {
        sendLogs = logs;
        totalSends = logs.length;
        hardestSendGrade = maxSend;
        hardestFlashGrade = maxFlash;
        loading = false;
      });
    } catch (e) {
      debugPrint("Error fetching logbook: $e");
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  String _formatGrade(int grade) => grade > 0 ? 'V$grade' : '-';

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("My Logbook")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // STATS
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatCard("Total Sends", totalSends.toString()),
                _buildStatCard(
                  "Hardest Send",
                  _formatGrade(hardestSendGrade),
                ),
                _buildStatCard(
                  "Hardest Flash",
                  _formatGrade(hardestFlashGrade),
                ),
              ],
            ),
            const SizedBox(height: 20),

            const Text(
              "Send History",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(),

            Expanded(
              child: sendLogs.isEmpty
                  ? const Center(child: Text("No sends logged yet."))
                  : ListView.builder(
                      itemCount: sendLogs.length,
                      itemBuilder: (context, index) {
                        final send = sendLogs[index];
                        final gradeNum = send['grade_num'] as int;

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: gradeNum <= 4
                                ? Colors.green
                                : gradeNum <= 8
                                    ? Colors.blue
                                    : Colors.red,
                            child: Text(
                              send['grade'],
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          title: Text(send['climb_name']),
                          subtitle: Text(
                            send['is_flash'] == true ? 'Flash' : 'Send',
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

  Widget _buildStatCard(String title, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(title, style: const TextStyle(color: Colors.grey)),
      ],
    );
  }
}
