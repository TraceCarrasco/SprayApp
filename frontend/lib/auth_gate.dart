/* Continuously listens to auth state
   Auth = user logged in
   Not auth = display sign in / register page
*/
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:namer_app/home.dart';
import 'package:namer_app/login_page.dart';
import 'package:namer_app/reset_password_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isRecovery = false;
  Session? _session;
  late final StreamSubscription<AuthState> _authSub;

  @override
  void initState() {
    super.initState();
    _session = Supabase.instance.client.auth.currentSession;
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (!mounted) return;
      setState(() {
        _session = state.session;
        if (state.event == AuthChangeEvent.passwordRecovery) {
          _isRecovery = true;
        } else if (state.event == AuthChangeEvent.signedOut ||
            state.event == AuthChangeEvent.userUpdated) {
          _isRecovery = false;
        }
      });
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isRecovery && _session != null) {
      return const ResetPasswordPage();
    }
    if (_session != null) {
      return HomeWithNav();
    }
    return LoginPage();
  }
}
