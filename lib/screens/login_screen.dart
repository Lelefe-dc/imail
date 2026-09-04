import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api_client.dart';
import '../branding.dart';
import '../mail_store.dart';

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

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MailStore>();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                  side: const BorderSide(color: Color(0xFFE3E8E5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(26, 28, 26, 30),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(child: IMailLogo(width: 285)),
                        const SizedBox(height: 24),
                        Text(
                          'Welcome to iMail',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: imailGreen,
                              ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Sign in with an email address already configured in Ithute Mail. Your inbox, folders and messages will load automatically.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF66736D), height: 1.45),
                        ),
                        const SizedBox(height: 28),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Email address',
                            prefixIcon: Icon(Icons.alternate_email_rounded),
                          ),
                          validator: (value) {
                            final v = value?.trim() ?? '';
                            if (!v.contains('@') || v.startsWith('@') || v.endsWith('@')) {
                              return 'Enter your configured email address';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: 'Mailbox password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              onPressed: () => setState(() => _obscure = !_obscure),
                              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            ),
                          ),
                          validator: (value) => (value?.isEmpty ?? true) ? 'Enter your mailbox password' : null,
                        ),
                        const SizedBox(height: 22),
                        FilledButton.icon(
                          onPressed: store.busy ? null : _submit,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(54),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          ),
                          icon: store.busy
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.login_rounded),
                          label: Text(store.busy ? 'Signing in…' : 'Sign in'),
                        ),
                        const SizedBox(height: 18),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.verified_user_outlined, size: 16, color: Color(0xFF7A8580)),
                            SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                'Your password is sent only to the Ithute Mail server and is not saved on this device.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12, color: Color(0xFF7A8580)),
                              ),
                            ),
                          ],
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
