import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'api_client.dart';
import 'app_lock.dart';
import 'branding.dart';
import 'mail_realtime_bridge.dart';
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
    final api = IMailApiClient();
    return MultiProvider(
      providers: [
        Provider<IMailApiClient>.value(value: api),
        ChangeNotifierProvider(create: (_) => MailStore(api)..bootstrap()),
      ],
      child: MailRealtimeBridge(
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
          home: const AppLockGate(child: _RootGate()),
        ),
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
      return const _IMailBootScreen();
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: store.authenticated
          ? const HomeScreen(key: ValueKey('mailbox'))
          : const LoginScreen(key: ValueKey('login')),
    );
  }
}

class _IMailBootScreen extends StatelessWidget {
  const _IMailBootScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF3F6FC),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IMailLogo(width: 255),
              SizedBox(height: 24),
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: imailGreen,
                ),
              ),
              SizedBox(height: 14),
              Text(
                'Opening your mail…',
                style: TextStyle(
                  color: Color(0xFF667085),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
