import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_service.dart';
import '../state/providers.dart';
import 'home_shell.dart';
import 'login_screen.dart';
import 'theme.dart';
import 'widgets/common.dart';

class MedBillsApp extends StatelessWidget {
  const MedBillsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MedBills',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return session.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: ErrorPanel(message: friendlyError(e))),
      data: (state) => switch (state) {
        SessionLoading() => const Scaffold(body: Center(child: CircularProgressIndicator())),
        SignedOut() => const LoginScreen(),
        NoStoreAccess(:final email) => NoAccessScreen(email: email),
        SignedIn() => const HomeShell(),
      },
    );
  }
}
