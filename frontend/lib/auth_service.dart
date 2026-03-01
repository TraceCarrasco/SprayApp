import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Sign in with email
  Future<AuthResponse> signInWithEmailPassword(
    String email,
    String password,
  ) async {
    return await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  // Validate username format
  String? validateUsername(String username) {
    if (username.isEmpty) {
      return 'Username cannot be empty';
    }
    if (username.length < 3) {
      return 'Username must be at least 3 characters';
    }
    if (username.length > 20) {
      return 'Username must be 20 characters or less';
    }
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(username)) {
      return 'Username can only contain letters, numbers, _ and -';
    }
    return null;
  }

  // Check if username is already taken
  Future<bool> isUsernameTaken(String username) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('id')
          .eq('display_name', username)
          .maybeSingle();
      return response != null;
    } catch (e) {
      // If profiles table doesn't exist yet or other error, allow attempt
      return false;
    }
  }

  // Sign up with email
  Future<AuthResponse> signUpWithEmailPassword(
    String email,
    String password,
    String username,
  ) async {
    // Validate username format
    final validationError = validateUsername(username);
    if (validationError != null) {
      throw AuthException(validationError);
    }

    // Check if username is taken
    final isTaken = await isUsernameTaken(username);
    if (isTaken) {
      throw AuthException('Username is already taken');
    }

    // Sign up with username in metadata
    // The database trigger will create the profile entry
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {'display_name': username},
    );

    // If signup was successful but trigger didn't create profile,
    // manually insert it (fallback)
    if (response.user != null) {
      try {
        await _supabase.from('profiles').upsert({
          'id': response.user!.id,
          'display_name': username,
        });
      } catch (e) {
        // Profile might already exist from trigger, that's ok
      }
    }

    return response;
  }

  // Sign out
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  // Delete account - permanently removes the user
Future<void> deleteAccount() async {
  final user = _supabase.auth.currentUser;
  if (user == null) {
    throw AuthException('No user logged in');
  }

  try {
    // Call the RPC function (no parameters needed)
    await _supabase.rpc('delete_user');
  } catch (e) {
    throw AuthException('Failed to delete account: $e');
  }
}

Future<void> deleteUserData(String userId) async {
  // This is now handled by the RPC function
  // Remove this method or keep it empty
}

  Future<void> sendPasswordResetEmail(String email) async {
    await _supabase.auth.resetPasswordForEmail(
      email,
      redirectTo: 'com.faspraywall.fahumboldtspraywall://login-callback',
    );
  }

  String? getCurrentEmail() {
    final session = _supabase.auth.currentSession;
    final user = session?.user;
    return user?.email;
  }

  // Get current user's display name
  String? getCurrentDisplayName() {
    final user = _supabase.auth.currentUser;
    return user?.userMetadata?['display_name'];
  }

  // Get current user ID
  String? getCurrentUserId() {
    return _supabase.auth.currentUser?.id;
  }
}