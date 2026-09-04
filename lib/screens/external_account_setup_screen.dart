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

  String? _domainFromEmail() {
    final email = _email.text.trim().toLowerCase();
    final at = email.lastIndexOf('@');
    if (at < 0 || at == email.length - 1) return null;
    return email.substring(at + 1);
  }

  void _applyDomainDefaults({bool revealManual = true}) {
    final domain = _domainFromEmail();
    if (domain == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the email address first.')),
      );
      return;
    }

    final email = _email.text.trim().toLowerCase();
    final mailHost = 'mail.$domain';
    _username.text = email;
    _imapHost.text = mailHost;
    _smtpHost.text = mailHost;
    _imapPort.text = '993';
    _smtpPort.text = '465';

    if (mounted) {
      setState(() {
        if (revealManual) _manual = true;
        _imapSecurity = SocketType.ssl;
        _smtpSecurity = SocketType.ssl;
      });
    }
  }

  MailAccount _manualAccount({
    required String email,
    required String password,
    required String displayName,
    required String accountName,
  }) {
    final incomingPort = int.tryParse(_imapPort.text.trim());
    final outgoingPort = int.tryParse(_smtpPort.text.trim());
    if (incomingPort == null || outgoingPort == null) {
      throw const FormatException('Enter valid IMAP and SMTP port numbers.');
    }

    final incomingHost = _imapHost.text.trim();
    final outgoingHost = _smtpHost.text.trim();
    if (incomingHost.isEmpty || outgoingHost.isEmpty) {
      throw const FormatException('Enter the incoming and outgoing mail servers.');
    }

    return MailAccount.fromManualSettings(
      name: accountName,
      email: email,
      incomingHost: incomingHost,
      outgoingHost: outgoingHost,
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

  Future<MailAccount> _buildAccount() async {
    final email = _email.text.trim().toLowerCase();
    final password = _password.text;
    final displayName = _name.text.trim();
    final accountName = displayName.isEmpty ? email : displayName;

    if (_manual) {
      return _manualAccount(
        email: email,
        password: password,
        displayName: displayName,
        accountName: accountName,
      );
    }

    final config = await Discover.discover(
      email,
      forceSslConnection: true,
      isLogEnabled: false,
    ).timeout(const Duration(seconds: 18));

    if (config != null && config.isValid) {
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

    // Many domain mailboxes do not publish automatic-discovery metadata.
    // Fall back to the common secure mail.<domain> layout before asking the
    // user to enter server settings manually.
    _applyDomainDefaults(revealManual: false);
    return _manualAccount(
      email: email,
      password: password,
      displayName: displayName,
      accountName: accountName,
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
      setState(() => _manual = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } on MailException catch (_) {
      if (!mounted) return;
      _applyDomainDefaults();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'iMail could not verify the account automatically. Review the server settings below and try again.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _applyDomainDefaults();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The account could not be verified automatically. Review the server settings below and try again.',
          ),
        ),
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

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFE7F3EE),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: imailGreen, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF202124),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: Color(0xFF667085),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF3F6FC),
        surfaceTintColor: const Color(0xFFF3F6FC),
        scrolledUnderElevation: 0,
        elevation: 0,
        title: const Text(
          'Add email account',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE4E9F0)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x08000000),
                      blurRadius: 14,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE2F1EB),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.alternate_email_rounded,
                            color: imailGreen,
                            size: 25,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Connect another email account',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF202124),
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'iMail can discover secure settings automatically or let you configure them yourself.',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: Color(0xFF667085),
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
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
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
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
                      onPressed: _busy ? null : () => _applyDomainDefaults(),
                      icon: const Icon(Icons.dns_outlined),
                      label: const Text('Use standard mail settings'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                    if (_manual) ...[
                      const SizedBox(height: 24),
                      const Divider(height: 1),
                      const SizedBox(height: 20),
                      _sectionHeader(
                        icon: Icons.move_to_inbox_outlined,
                        title: 'Incoming mail',
                        subtitle: 'IMAP receives and synchronizes your messages.',
                      ),
                      const SizedBox(height: 16),
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
                      const SizedBox(height: 24),
                      _sectionHeader(
                        icon: Icons.send_outlined,
                        title: 'Outgoing mail',
                        subtitle: 'SMTP sends messages from this account.',
                      ),
                      const SizedBox(height: 16),
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
                        minimumSize: const Size.fromHeight(54),
                        backgroundColor: imailGreen,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
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
                    const SizedBox(height: 16),
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
                            'External account credentials are protected in secure storage on this device. Secure encrypted connections are used by default.',
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
