import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api_client.dart';
import '../branding.dart';
import '../external_account_store.dart';
import '../mail_store.dart';
import 'external_account_setup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _connecting = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await context.read<MailStore>().login(_email.text, _password.text);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _connectAnother() async {
    if (_connecting) return;
    final account = await Navigator.of(context).push<MailAccount>(
      MaterialPageRoute(builder: (_) => const ExternalAccountSetupScreen()),
    );
    if (account == null || !mounted) return;

    final authentication = account.incoming.authentication;
    if (authentication is! PlainAuthentication) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This account requires an interactive authentication method.')),
      );
      return;
    }

    setState(() => _connecting = true);
    try {
      await context.read<MailStore>().login(account.email, authentication.password);
    } on ApiException {
      // The direct IMAP/SMTP setup succeeded, but the backend registration may
      // have been temporarily unavailable. Retry registration once so future
      // sign-ins use the fast known-account path.
      final synced = await ExternalAccountStore().syncKnownAccount(account);
      if (!mounted) return;
      if (!synced) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The mailbox is verified, but iMail could not register it with the mail service yet. Try again when the connection is stable.')),
        );
        return;
      }
      try {
        await context.read<MailStore>().login(account.email, authentication.password);
      } on ApiException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MailStore>();
    final busy = store.busy || _connecting;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FC),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 28),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 60),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(child: IMailLogo(width: 275)),
                        const SizedBox(height: 32),
                        Container(
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x0B000000),
                                blurRadius: 22,
                                offset: Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Sign in to iMail',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF252A2E),
                                  fontSize: 25,
                                  letterSpacing: -0.4,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Open an Ithute mailbox or any email account that has already been connected to iMail.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF687078),
                                  fontSize: 14,
                                  height: 1.45,
                                ),
                              ),
                              const SizedBox(height: 26),
                              TextFormField(
                                controller: _email,
                                enabled: !busy,
                                keyboardType: TextInputType.emailAddress,
                                autocorrect: false,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.email],
                                decoration: const InputDecoration(
                                  labelText: 'Email address',
                                  hintText: 'name@company.co.ls',
                                  prefixIcon: Icon(Icons.alternate_email_rounded),
                                ),
                                validator: (value) {
                                  final v = value?.trim() ?? '';
                                  if (!v.contains('@') || v.startsWith('@') || v.endsWith('@')) {
                                    return 'Enter your email address';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _password,
                                enabled: !busy,
                                obscureText: _obscure,
                                textInputAction: TextInputAction.done,
                                autofillHints: const [AutofillHints.password],
                                onFieldSubmitted: (_) => _submit(),
                                decoration: InputDecoration(
                                  labelText: 'Mailbox password',
                                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                                  suffixIcon: IconButton(
                                    tooltip: _obscure ? 'Show password' : 'Hide password',
                                    onPressed: busy ? null : () => setState(() => _obscure = !_obscure),
                                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                  ),
                                ),
                                validator: (value) => (value?.isEmpty ?? true) ? 'Enter your mailbox password' : null,
                              ),
                              const SizedBox(height: 22),
                              FilledButton(
                                onPressed: busy ? null : _submit,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(54),
                                  backgroundColor: imailGreen,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                ),
                                child: busy
                                    ? const SizedBox.square(
                                        dimension: 21,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Text('Open mailbox', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: busy ? null : _connectAnother,
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Connect another email account', style: TextStyle(fontWeight: FontWeight.w700)),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(52),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                ),
                              ),
                              const SizedBox(height: 18),
                              const Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.shield_outlined, size: 17, color: Color(0xFF7A8388)),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Once an external mailbox has been verified, its server settings are remembered securely so normal sign-in does not repeat discovery.',
                                      style: TextStyle(fontSize: 12, height: 1.4, color: Color(0xFF7A8388)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
