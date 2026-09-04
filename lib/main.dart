import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'api_client.dart';
import 'branding.dart';
import 'mail_store.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const IMailApp());
}

class IMailApp extends StatelessWidget {
  const IMailApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MailStore(IMailApiClient())..bootstrap(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'iMail',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: imailGreen,
            primary: imailGreen,
            secondary: imailGold,
            surface: Colors.white,
          ),
          scaffoldBackgroundColor: imailSurface,
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0xFFE5E9E7)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: imailEmerald, width: 1.4),
            ),
          ),
        ),
        home: const _RootGate(),
      ),
    );
  }
}

class _RootGate extends StatelessWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MailStore>();
    if (store.booting) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IMailLogo(width: 250),
              SizedBox(height: 28),
              CircularProgressIndicator(strokeWidth: 2.5),
            ],
          ),
        ),
      );
    }
    return store.authenticated ? const HomeScreen() : const LoginScreen();
  }
}
