import 'package:flutter/material.dart';
import 'package:namer_app/auth_service.dart';
import 'package:namer_app/my_sets.dart';
import 'package:namer_app/climb_display.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'logbook.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final authService = AuthService();
  String username = "";
  List<Map<String, dynamic>> recentActivity = [];
  bool loadingActivity = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadRecentActivity();
  }

  void logout() async {
    await authService.signOut();
  }

  void openLogbook() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LogbookPage()),
    );
  }

  void openMySets() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const MySetsPage()),
    );
  }

  void openAllActivity() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AllActivityPage()),
    );
  }

  void _openClimb(BuildContext context, String climbId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClimbDisplay(climbId: climbId),
      ),
    );
  }

  Future<void> _loadUserData() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      setState(() {
        username = user.userMetadata?['display_name'] ?? '';
      });
    }
  }

  Future<void> _loadRecentActivity() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final currentUserId = user.id;

    try {
      List<Map<String, dynamic>> activities = [];

      final createdClimbs = await Supabase.instance.client
          .from('climbs')
          .select('climbid, name, grade, createdat, displayname, private, id')
          .order('createdat', ascending: false);

      for (final climb in createdClimbs) {
        final isPrivate = climb['private'] == true;
        final creatorId = climb['id'];

        if (isPrivate && creatorId != currentUserId) {
          continue;
        }

        activities.add({
          'type': 'created',
          'climb_id': climb['climbid'].toString(),
          'climb_name': climb['name'] ?? 'Unknown',
          'grade': climb['grade'] ?? '',
          'timestamp': climb['createdat'],
          'display_name': climb['displayname'] ?? '',
          'is_private': isPrivate,
        });
      }

      final climbsWithAscents = await Supabase.instance.client
          .from('climbs')
          .select('climbid, name, grade, ascents, private, id')
          .not('ascents', 'is', null);

      for (final climb in climbsWithAscents) {
        final isPrivate = climb['private'] == true;
        final creatorId = climb['id'];

        if (isPrivate && creatorId != currentUserId) {
          continue;
        }

        final ascents = climb['ascents'] as List<dynamic>? ?? [];
        for (final ascent in ascents) {
          activities.add({
            'type': 'sent',
            'climb_id': climb['climbid'].toString(),
            'climb_name': climb['name'] ?? 'Unknown',
            'grade': climb['grade'] ?? '',
            'timestamp': ascent['timestamp'],
            'is_flash': ascent['is_flash'] ?? false,
            'display_name': ascent['username'] ?? '',
            'is_private': isPrivate,
          });
        }
      }

      activities.sort((a, b) {
        final timestampA = a['timestamp'] ?? '';
        final timestampB = b['timestamp'] ?? '';
        return timestampB.compareTo(timestampA);
      });

      setState(() {
        recentActivity = activities.take(5).toList();
        loadingActivity = false;
      });
    } catch (e) {
      debugPrint("Error loading recent activity: $e");
      setState(() {
        loadingActivity = false;
      });
    }
  }

  String _formatTimestamp(String? timestamp) {
    if (timestamp == null) return '';
    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inDays == 0) {
        if (difference.inHours == 0) {
          if (difference.inMinutes == 0) return 'Just now';
          return '${difference.inMinutes}m ago';
        }
        return '${difference.inHours}h ago';
      } else if (difference.inDays == 1) {
        return 'Yesterday';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
      }
    } catch (e) {
      return '';
    }
  }

  /// Check if a username is already taken by another user
  Future<bool> _isUsernameTaken(String newName) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return true;

    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('id')
          .eq('display_name', newName)
          .neq('id', user.id) // Exclude current user
          .maybeSingle();

      return response != null;
    } catch (e) {
      debugPrint("Error checking username: $e");
      return false; // Allow attempt if check fails
    }
  }

  /// Validate username format
  String? _validateUsername(String name) {
    if (name.isEmpty) {
      return 'Username cannot be empty';
    }
    if (name.length < 3) {
      return 'Username must be at least 3 characters';
    }
    if (name.length > 20) {
      return 'Username must be 20 characters or less';
    }
    // Only allow letters, numbers, underscores, and hyphens
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(name)) {
      return 'Username can only contain letters, numbers, _ and -';
    }
    return null;
  }

  void _showEditNameDialog() {
    final controller = TextEditingController(text: username);
    String? errorText;
    bool isChecking = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text("Edit Display Name"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: "Display Name",
                    errorText: errorText,
                    helperText: "3-20 characters, letters, numbers, _ or -",
                    suffixIcon: isChecking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                  onChanged: (value) {
                    // Clear error when user types
                    if (errorText != null) {
                      setDialogState(() {
                        errorText = null;
                      });
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: isChecking
                    ? null
                    : () async {
                        final newName = controller.text.trim();

                        // Validate format first
                        final validationError = _validateUsername(newName);
                        if (validationError != null) {
                          setDialogState(() {
                            errorText = validationError;
                          });
                          return;
                        }

                        // Check if same as current username
                        if (newName.toLowerCase() == username.toLowerCase()) {
                          Navigator.of(context).pop();
                          return;
                        }

                        // Check if username is taken
                        setDialogState(() {
                          isChecking = true;
                          errorText = null;
                        });

                        final isTaken = await _isUsernameTaken(newName);

                        if (isTaken) {
                          setDialogState(() {
                            isChecking = false;
                            errorText = 'Username is already taken';
                          });
                          return;
                        }

                        setDialogState(() {
                          isChecking = false;
                        });

                        // Update username
                        Navigator.of(context).pop();
                        _updateDisplayName(newName);
                      },
                child: const Text("Save"),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _updateDisplayName(String newName) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      // Update profiles table
      await Supabase.instance.client.from('profiles').upsert({
        'id': user.id,
        'display_name': newName,
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Update auth user metadata
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: {'display_name': newName}),
      );

      setState(() => username = newName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ Display name updated"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on PostgrestException catch (e) {
      debugPrint("Postgrest error: ${e.code} - ${e.message}");

      String errorMessage = "Error updating name";
      if (e.code == '23505') {
        // Unique constraint violation
        errorMessage = "Username is already taken";
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ $errorMessage"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error updating display name: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ Error updating name: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showSettingsMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Settings',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Change Display Name'),
                onTap: () {
                  Navigator.pop(context);
                  _showEditNameDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Sign Out'),
                onTap: () {
                  Navigator.pop(context);
                  logout();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActivityItem(Map<String, dynamic> activity) {
    final climbId = activity['climb_id'] as String?;
    final type = activity['type'];
    final climbName = activity['climb_name'] ?? 'Unknown';
    final grade = activity['grade'] ?? '';
    final timestamp = _formatTimestamp(activity['timestamp']);
    final isFlash = activity['is_flash'] ?? false;
    final userName = activity['display_name'] ?? 'User';
    final isPrivate = activity['is_private'] ?? false;

    IconData icon;
    Color iconColor;
    String actionText;

    if (type == 'created') {
      icon = Icons.add_circle_outline;
      iconColor = Colors.green;
      actionText = 'created';
    } else {
      icon = isFlash ? Icons.flash_on : Icons.check_circle_outline;
      iconColor = isFlash ? Colors.amber : Colors.blue;
      actionText = isFlash ? 'flashed' : 'sent';
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        onTap: climbId == null ? null : () => _openClimb(context, climbId),
        leading: CircleAvatar(
          backgroundColor: iconColor.withOpacity(0.1),
          child: Icon(icon, color: iconColor),
        ),
        title: Row(
          children: [
            Text(
              "$userName ",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              actionText,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: iconColor,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                climbName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (grade.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  grade,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
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
        subtitle: Text(
          timestamp,
          style: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 12,
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Image.asset(
          'assets/FA_logo.png',
          height: 60,
          fit: BoxFit.contain,
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: "Settings",
            onPressed: _showSettingsMenu,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    username.isNotEmpty
                        ? username
                        : "Tap settings to set name",
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: openLogbook,
                          icon: const Icon(Icons.book, size: 18),
                          label: const Text("Logbook"),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: openMySets,
                          icon: const Icon(Icons.construction, size: 18),
                          label: const Text("My Sets"),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.history, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          "Recent Activity",
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: loadingActivity
                          ? const Center(child: CircularProgressIndicator())
                          : recentActivity.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.inbox_outlined,
                                        size: 48,
                                        color: Colors.grey.shade400,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        "No recent activity",
                                        style: TextStyle(
                                          color: Colors.grey.shade500,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "Start climbing to see your activity here!",
                                        style: TextStyle(
                                          color: Colors.grey.shade400,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: recentActivity.length,
                                  itemBuilder: (context, index) {
                                    return _buildActivityItem(
                                        recentActivity[index]);
                                  },
                                ),
                    ),
                    if (!loadingActivity && recentActivity.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Center(
                          child: TextButton.icon(
                            onPressed: openAllActivity,
                            icon: const Icon(Icons.arrow_forward),
                            label: const Text("View All Activity"),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// -------------------------
/// ALL ACTIVITY PAGE
/// -------------------------
class AllActivityPage extends StatefulWidget {
  const AllActivityPage({super.key});

  @override
  State<AllActivityPage> createState() => _AllActivityPageState();
}

class _AllActivityPageState extends State<AllActivityPage> {
  List<Map<String, dynamic>> allActivity = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadAllActivity();
  }

  void _openClimb(BuildContext context, String climbId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClimbDisplay(climbId: climbId),
      ),
    );
  }

  Future<void> _loadAllActivity() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final currentUserId = user.id;

    try {
      List<Map<String, dynamic>> activities = [];

      final createdClimbs = await Supabase.instance.client
          .from('climbs')
          .select('climbid, name, grade, createdat, displayname, private, id')
          .order('createdat', ascending: false);

      for (final climb in createdClimbs) {
        final isPrivate = climb['private'] == true;
        final creatorId = climb['id'];

        if (isPrivate && creatorId != currentUserId) {
          continue;
        }

        activities.add({
          'type': 'created',
          'climb_id': climb['climbid'].toString(),
          'climb_name': climb['name'] ?? 'Unknown',
          'grade': climb['grade'] ?? '',
          'timestamp': climb['createdat'],
          'display_name': climb['displayname'] ?? '',
          'is_private': isPrivate,
        });
      }

      final climbsWithAscents = await Supabase.instance.client
          .from('climbs')
          .select('climbid, name, grade, ascents, private, id')
          .not('ascents', 'is', null);

      for (final climb in climbsWithAscents) {
        final isPrivate = climb['private'] == true;
        final creatorId = climb['id'];

        if (isPrivate && creatorId != currentUserId) {
          continue;
        }

        final ascents = climb['ascents'] as List<dynamic>? ?? [];
        for (final ascent in ascents) {
          activities.add({
            'type': 'sent',
            'climb_id': climb['climbid'].toString(),
            'climb_name': climb['name'] ?? 'Unknown',
            'grade': climb['grade'] ?? '',
            'timestamp': ascent['timestamp'],
            'is_flash': ascent['is_flash'] ?? false,
            'display_name': ascent['username'] ?? '',
            'is_private': isPrivate,
          });
        }
      }

      activities.sort((a, b) {
        final timestampA = a['timestamp'] ?? '';
        final timestampB = b['timestamp'] ?? '';
        return timestampB.compareTo(timestampA);
      });

      setState(() {
        allActivity = activities;
        loading = false;
      });
    } catch (e) {
      debugPrint("Error loading all activity: $e");
      setState(() {
        loading = false;
      });
    }
  }

  String _formatTimestamp(String? timestamp) {
    if (timestamp == null) return '';
    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inDays == 0) {
        if (difference.inHours == 0) {
          if (difference.inMinutes == 0) return 'Just now';
          return '${difference.inMinutes}m ago';
        }
        return '${difference.inHours}h ago';
      } else if (difference.inDays == 1) {
        return 'Yesterday';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
      }
    } catch (e) {
      return '';
    }
  }

  Widget _buildActivityItem(Map<String, dynamic> activity) {
    final climbId = activity['climb_id'] as String?;
    final displayName = activity['display_name'] ?? 'User';
    final type = activity['type'];
    final climbName = activity['climb_name'] ?? 'Unknown';
    final grade = activity['grade'] ?? '';
    final timestamp = _formatTimestamp(activity['timestamp']);
    final isFlash = activity['is_flash'] ?? false;
    final isPrivate = activity['is_private'] ?? false;

    IconData icon;
    Color iconColor;
    String actionText;

    if (type == 'created') {
      icon = Icons.add_circle_outline;
      iconColor = Colors.green;
      actionText = 'Created';
    } else {
      icon = isFlash ? Icons.flash_on : Icons.check_circle_outline;
      iconColor = isFlash ? Colors.amber : Colors.blue;
      actionText = isFlash ? 'Flashed' : 'Sent';
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: ListTile(
        onTap: climbId == null ? null : () => _openClimb(context, climbId),
        leading: CircleAvatar(
          backgroundColor: iconColor.withOpacity(0.1),
          child: Icon(icon, color: iconColor),
        ),
        title: Row(
          children: [
            Text(
              "$displayName ",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              actionText,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: iconColor,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                climbName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (grade.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  grade,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
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
        subtitle: Text(
          timestamp,
          style: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 12,
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("All Activity"),
        centerTitle: true,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : allActivity.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "No activity yet",
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: allActivity.length,
                  itemBuilder: (context, index) =>
                      _buildActivityItem(allActivity[index]),
                ),
    );
  }
}