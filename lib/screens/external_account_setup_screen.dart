import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/material.dart';

import '../branding.dart';
import '../external_account_store.dart';

class ExternalAccountSetupScreen extends StatefulWidget {
  const ExternalAccountSetupScreen({super.key});

  @override
  State<ExternalAccountSetupScreen> createState() =>
      _ExternalAccountSetupScreenState();
}

class _ExternalAccountSetupScreenState
    extends State<ExternalAccountSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _username = TextEditingController();
  final _imapHost = TextEditingController();
  final _imapPort = TextEditingController(text: '993');
  final _smtpHost = TextEditingController();
  final _smtpPort = TextEditingController(text: '465');

  bool _manual = false;
  bool _busy = false;
  bool _obscure = true;
  SocketType _imapSecurity = SocketType.ssl;
  SocketType _smtpSecurity = SocketType.ssl;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _username.dispose();
    _imapHost.dispose();
    _imapPort.dispose();
    _smtpHost.dispose();
    _smtpPort.dispose();
    super.dispose();
  }

  String? _emailValidator(String? value) {
    final text = value?.trim() ?? '';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  void _fillDomainDefaults() {
    final email = _email.text.trim().toLowerCase();
    final at = email.lastIndexOf('@');
    if (at < 0 || at == email.length - 1) return;
    final domain = email.substring(at + 1);
    final mailHost = 'mail.$domain';
    _username.text = email;
    _imapHost.text = mailHost;
    _smtpHost.text = mailHost;
    _imapPort.text = '993';
    _smtpPort.text = '465';
    setState(() {
      _manual = true;
      _imapSecurity = SocketType.ssl;
      _smtpSecurity = SocketType.ssl;
    });
  }

  Future<MailAccount> _buildAccount() async {
    final email = _email.text.trim().toLowerCase();
    final password = _password.text;
    final displayName = _name.text.trim();
    final accountName = displayName.isEmpty ? email : displayName;

    if (!_manual) {
      final config = await Discover.discover(
        email,
        forceSslConnection: true,
        isLogEnabled: false,
      ).timeout(const Duration(seconds: 18));
      if (config == null || config.isNotValid) {
        throw const FormatException(
          'Automatic setup could not find secure IMAP/SMTP settings. Use Manual setup.',
        );
      }
      return MailAccount.fromDiscoveredSettings(
        name: accountName,
        email: email,
        password: password,
        config: config,
        userName: displayName,
        loginName: email,
        outgoingClientDomain: 'ithute.co.ls',
      );
    }

    final incomingPort = int.tryParse(_imapPort.text.trim());
    final outgoingPort = int.tryParse(_smtpPort.text.trim());
    if (incomingPort == null || outgoingPort == null) {
      throw const FormatException('Enter valid IMAP and SMTP port numbers.');
    }

    return MailAccount.fromManualSettings(
      name: accountName,
      email: email,
      incomingHost: _imapHost.text.trim(),
      outgoingHost: _smtpHost.text.trim(),
      password: password,
      userName: displayName,
      loginName: _username.text.trim().isEmpty
          ? email
          : _username.text.trim(),
      incomingType: ServerType.imap,
      outgoingType: ServerType.smtp,
      incomingPort: incomingPort,
      outgoingPort: outgoingPort,
      incomingSocketType: _imapSecurity,
      outgoingSocketType: _smtpSecurity,
      outgoingClientDomain: 'ithute.co.ls',
    );
  }

  Future<void> _connectAndSave() async {
    if (!_formKey.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _busy = true);

    MailClient? client;
    try {
      final account = await _buildAccount();
      client = MailClient(
        account,
        isLogEnabled: false,
        defaultResponseTimeout: const Duration(seconds: 12),
      );
      await client.connect(timeout: const Duration(seconds: 20));
      await client.listMailboxes();
      await client.disconnect();
      client = null;

      await ExternalAccountStore().saveAccount(account);
      if (!mounted) return;
      Navigator.pop(context, account);
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } on MailException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not connect to this mail server. Check the email, password, host, ports and SSL settings.\n$e',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Account setup failed: $e')),
      );
    } finally {
      if (client != null) {
        try {
          await client.disconnect();
        } catch (_) {}
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF3F6FC),
        surfaceTintColor: const Color(0xFFF3F6FC),
        title: const Text('Add email account'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Use iMail with another provider',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF202124),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Connect any standard IMAP + SMTP mailbox. iMail can try secure automatic discovery, or you can enter the server settings yourself.',
                      style: TextStyle(
                        color: Color(0xFF667085),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 22),
                    TextFormField(
                      controller: _name,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Your name',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      validator: _emailValidator,
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        hintText: 'you@yourdomain.co.ls',
                        prefixIcon: Icon(Icons.alternate_email_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      textInputAction:
                          _manual ? TextInputAction.next : TextInputAction.done,
                      onFieldSubmitted: (_) {
                        if (!_manual && !_busy) _connectAndSave();
                      },
                      validator: (value) => (value?.isEmpty ?? true)
                          ? 'Enter the mailbox password'
                          : null,
                      decoration: InputDecoration(
                        labelText: 'Mailbox password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment<bool>(
                          value: false,
                          label: Text('Automatic'),
                          icon: Icon(Icons.auto_fix_high_rounded),
                        ),
                        ButtonSegment<bool>(
                          value: true,
                          label: Text('Manual'),
                          icon: Icon(Icons.tune_rounded),
                        ),
                      ],
                      selected: {_manual},
                      onSelectionChanged: _busy
                          ? null
                          : (selection) => setState(
                                () => _manual = selection.first,
                              ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _fillDomainDefaults,
                      icon: const Icon(Icons.dns_outlined),
                      label: const Text('Use standard domain defaults'),
                    ),
                    if (_manual) ...[
                      const SizedBox(height: 22),
                      const Divider(),
                      const SizedBox(height: 12),
                      const Text(
                        'Incoming mail (IMAP)',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _username,
                        validator: (value) => (value?.trim().isEmpty ?? true)
                            ? 'Enter the server username'
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          hintText: 'Usually your full email address',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _imapHost,
                        validator: (value) => (value?.trim().isEmpty ?? true)
                            ? 'Enter the IMAP server'
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'IMAP server',
                          hintText: 'mail.yourdomain.co.ls',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _imapPort,
                              keyboardType: TextInputType.number,
                              decoration:
                                  const InputDecoration(labelText: 'Port'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _SecurityDropdown(
                              value: _imapSecurity,
                              onChanged: (value) =>
                                  setState(() => _imapSecurity = value),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'Outgoing mail (SMTP)',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _smtpHost,
                        validator: (value) => (value?.trim().isEmpty ?? true)
                            ? 'Enter the SMTP server'
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'SMTP server',
                          hintText: 'mail.yourdomain.co.ls',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _smtpPort,
                              keyboardType: TextInputType.number,
                              decoration:
                                  const InputDecoration(labelText: 'Port'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _SecurityDropdown(
                              value: _smtpSecurity,
                              onChanged: (value) =>
                                  setState(() => _smtpSecurity = value),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _busy ? null : _connectAndSave,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        backgroundColor: imailGreen,
                      ),
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.login_rounded),
                      label: Text(_busy ? 'Checking account…' : 'Connect account'),
                    ),
                    const SizedBox(height: 14),
                    const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 18,
                          color: Color(0xFF667085),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'External account credentials are stored only in secure storage on this device. SSL/TLS is the default.',
                            style: TextStyle(
                              color: Color(0xFF667085),
                              fontSize: 12,
                              height: 1.45,
                            ),
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
    );
  }
}

class _SecurityDropdown extends StatelessWidget {
  const _SecurityDropdown({required this.value, required this.onChanged});

  final SocketType value;
  final ValueChanged<SocketType> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<SocketType>(
      value: value,
      decoration: const InputDecoration(labelText: 'Security'),
      items: const [
        DropdownMenuItem(value: SocketType.ssl, child: Text('SSL/TLS')),
        DropdownMenuItem(value: SocketType.starttls, child: Text('STARTTLS')),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}
