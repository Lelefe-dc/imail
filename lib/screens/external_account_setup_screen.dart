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
  static const _connectTimeout = Duration(seconds: 6);
  static const _responseTimeout = Duration(seconds: 5);
  static const _discoverTimeout = Duration(seconds: 6);

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _username = TextEditingController();
  final _imapHost = TextEditingController();
  final _imapPort = TextEditingController(text: '993');
  final _smtpHost = TextEditingController();
  final _smtpPort = TextEditingController(text: '587');

  bool _manual = false;
  bool _busy = false;
  bool _obscure = true;
  String _status = '';
  SocketType _imapSecurity = SocketType.ssl;
  SocketType _smtpSecurity = SocketType.starttls;

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

  void _setStatus(String value) {
    if (!mounted) return;
    setState(() => _status = value);
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
    _smtpPort.text = '587';

    if (mounted) {
      setState(() {
        if (revealManual) _manual = true;
        _imapSecurity = SocketType.ssl;
        _smtpSecurity = SocketType.starttls;
      });
    }
  }

  MailAccount _manualAccount({
    required String email,
    required String password,
    required String displayName,
    required String accountName,
    String? incomingHost,
    int? incomingPort,
    SocketType? incomingSecurity,
    String? outgoingHost,
    int? outgoingPort,
    SocketType? outgoingSecurity,
  }) {
    final parsedIncomingPort =
        incomingPort ?? int.tryParse(_imapPort.text.trim());
    final parsedOutgoingPort =
        outgoingPort ?? int.tryParse(_smtpPort.text.trim());
    if (parsedIncomingPort == null || parsedOutgoingPort == null) {
      throw const FormatException('Enter valid IMAP and SMTP port numbers.');
    }

    final resolvedIncomingHost = incomingHost ?? _imapHost.text.trim();
    final resolvedOutgoingHost = outgoingHost ?? _smtpHost.text.trim();
    if (resolvedIncomingHost.isEmpty || resolvedOutgoingHost.isEmpty) {
      throw const FormatException('Enter the incoming and outgoing mail servers.');
    }

    return MailAccount.fromManualSettings(
      name: accountName,
      email: email,
      incomingHost: resolvedIncomingHost,
      outgoingHost: resolvedOutgoingHost,
      password: password,
      userName: displayName,
      loginName: _username.text.trim().isEmpty
          ? email
          : _username.text.trim(),
      incomingType: ServerType.imap,
      outgoingType: ServerType.smtp,
      incomingPort: parsedIncomingPort,
      outgoingPort: parsedOutgoingPort,
      incomingSocketType: incomingSecurity ?? _imapSecurity,
      outgoingSocketType: outgoingSecurity ?? _smtpSecurity,
      outgoingClientDomain: 'ithute.co.ls',
    );
  }

  Future<void> _verifyIncoming(MailAccount account) async {
    final mailConfig = account.incoming;
    final config = mailConfig.serverConfig;
    if (config.type != ServerType.imap) {
      throw const _MailSetupException(
        'Incoming server is not configured for IMAP.',
        stage: 'incoming',
      );
    }

    final client = ImapClient(
      isLogEnabled: false,
      defaultWriteTimeout: _responseTimeout,
      defaultResponseTimeout: _responseTimeout,
    );
    try {
      final isSecure = config.socketType == SocketType.ssl;
      await client.connectToServer(
        config.hostname,
        config.port,
        isSecure: isSecure,
        timeout: _connectTimeout,
      );
      if (!isSecure) {
        if (client.serverInfo.supportsStartTls &&
            config.socketType != SocketType.plainNoStartTls) {
          await client.startTls();
        } else if (config.socketType == SocketType.starttls) {
          throw const _MailSetupException(
            'The incoming server did not offer the required secure STARTTLS connection.',
            stage: 'incoming',
          );
        }
      }
      await mailConfig.authentication.authenticate(config, imap: client);
      await client.listMailboxes(recursive: false);
    } catch (e) {
      if (e is _MailSetupException) rethrow;
      throw _MailSetupException(
        _friendlyServerError(e, stage: 'incoming'),
        stage: 'incoming',
        cause: e,
      );
    } finally {
      try {
        await client.disconnect();
      } catch (_) {}
    }
  }

  Future<void> _verifyOutgoing(MailAccount account) async {
    final mailConfig = account.outgoing;
    final config = mailConfig.serverConfig;
    if (config.type != ServerType.smtp) {
      throw const _MailSetupException(
        'Outgoing server is not configured for SMTP.',
        stage: 'outgoing',
      );
    }

    final client = SmtpClient(
      account.outgoingClientDomain,
      isLogEnabled: false,
    );
    try {
      final isSecure = config.socketType == SocketType.ssl;
      await client.connectToServer(
        config.hostname,
        config.port,
        isSecure: isSecure,
        timeout: _connectTimeout,
      );
      await client.ehlo();
      if (!isSecure) {
        if (client.serverInfo.supportsStartTls &&
            config.socketType != SocketType.plainNoStartTls) {
          await client.startTls();
        } else if (config.socketType == SocketType.starttls) {
          throw const _MailSetupException(
            'The outgoing server did not offer the required secure STARTTLS connection.',
            stage: 'outgoing',
          );
        }
      }
      await mailConfig.authentication.authenticate(config, smtp: client);
    } catch (e) {
      if (e is _MailSetupException) rethrow;
      throw _MailSetupException(
        _friendlyServerError(e, stage: 'outgoing'),
        stage: 'outgoing',
        cause: e,
      );
    } finally {
      try {
        await client.disconnect();
      } catch (_) {}
    }
  }

  String _friendlyServerError(Object error, {required String stage}) {
    final raw = error.toString();
    final lower = raw.toLowerCase();
    final label = stage == 'outgoing' ? 'outgoing SMTP' : 'incoming IMAP';

    if (lower.contains('timed out') ||
        lower.contains('timeout') ||
        lower.contains('connection refused') ||
        lower.contains('failed host lookup') ||
        lower.contains('socketexception') ||
        lower.contains('network is unreachable')) {
      return 'iMail could not reach the $label server. This is a server, port, security or network problem and does not mean your mailbox password is incorrect.';
    }

    if (lower.contains('certificate') ||
        lower.contains('handshake') ||
        lower.contains('tls') ||
        lower.contains('ssl')) {
      return 'iMail reached the $label server but could not establish its secure connection. Check the server name, port and SSL/TLS setting.';
    }

    if (lower.contains('auth') ||
        lower.contains('login') ||
        lower.contains('credential') ||
        lower.contains('535') ||
        lower.contains('username') ||
        lower.contains('password')) {
      return 'The $label server rejected authentication. iMail cannot conclude that the password is wrong: the username, port, security mode or server authentication policy may be different. Review the account server settings.';
    }

    return 'The $label server could not be verified. Review its host, port and security settings and try again.';
  }

  Future<MailAccount?> _tryAccount(
    MailAccount account, {
    required bool verifyIncoming,
    required bool verifyOutgoing,
  }) async {
    try {
      if (verifyIncoming) await _verifyIncoming(account);
      if (verifyOutgoing) await _verifyOutgoing(account);
      return account;
    } catch (_) {
      return null;
    }
  }

  Future<MailAccount> _automaticAccount({
    required String email,
    required String password,
    required String displayName,
    required String accountName,
  }) async {
    _setStatus('Finding secure mail settings…');

    ClientConfig? discovered;
    try {
      discovered = await Discover.discover(
        email,
        forceSslConnection: false,
        isLogEnabled: false,
      ).timeout(_discoverTimeout);
    } catch (_) {
      discovered = null;
    }

    if (discovered != null && discovered.isValid) {
      final account = MailAccount.fromDiscoveredSettings(
        name: accountName,
        email: email,
        password: password,
        config: discovered,
        userName: displayName,
        loginName: email,
        outgoingClientDomain: 'ithute.co.ls',
      );
      _setStatus('Checking incoming mail…');
      try {
        await _verifyIncoming(account);
        _setStatus('Checking outgoing mail…');
        await _verifyOutgoing(account);
        return account;
      } catch (_) {
        // Continue with secure domain-based fallbacks. Auto-discovery records
        // are frequently absent or stale on custom-domain mail servers.
      }
    }

    final domain = _domainFromEmail();
    if (domain == null) {
      throw const _MailSetupException(
        'Enter a valid email address.',
        stage: 'account',
      );
    }

    final incomingCandidates = <({String host, int port, SocketType security})>[
      (host: 'mail.$domain', port: 993, security: SocketType.ssl),
      (host: 'imap.$domain', port: 993, security: SocketType.ssl),
      (host: 'mail.$domain', port: 143, security: SocketType.starttls),
    ];

    MailAccount? incomingWorkingAccount;
    _setStatus('Checking incoming mail…');
    for (final candidate in incomingCandidates) {
      final account = _manualAccount(
        email: email,
        password: password,
        displayName: displayName,
        accountName: accountName,
        incomingHost: candidate.host,
        incomingPort: candidate.port,
        incomingSecurity: candidate.security,
        outgoingHost: 'mail.$domain',
        outgoingPort: 587,
        outgoingSecurity: SocketType.starttls,
      );
      final working = await _tryAccount(
        account,
        verifyIncoming: true,
        verifyOutgoing: false,
      );
      if (working != null) {
        incomingWorkingAccount = working;
        break;
      }
    }

    if (incomingWorkingAccount == null) {
      throw const _MailSetupException(
        'iMail could not verify the incoming mail server automatically. Your password has not been marked incorrect. Review the IMAP server settings.',
        stage: 'incoming',
      );
    }

    final incoming = incomingWorkingAccount.incoming.serverConfig;
    final outgoingCandidates = <({String host, int port, SocketType security})>[
      (host: 'mail.$domain', port: 587, security: SocketType.starttls),
      (host: 'mail.$domain', port: 465, security: SocketType.ssl),
      (host: 'smtp.$domain', port: 587, security: SocketType.starttls),
      (host: 'smtp.$domain', port: 465, security: SocketType.ssl),
    ];

    _setStatus('Checking outgoing mail…');
    for (final candidate in outgoingCandidates) {
      final account = _manualAccount(
        email: email,
        password: password,
        displayName: displayName,
        accountName: accountName,
        incomingHost: incoming.hostname,
        incomingPort: incoming.port,
        incomingSecurity: incoming.socketType,
        outgoingHost: candidate.host,
        outgoingPort: candidate.port,
        outgoingSecurity: candidate.security,
      );
      final working = await _tryAccount(
        account,
        verifyIncoming: false,
        verifyOutgoing: true,
      );
      if (working != null) return working;
    }

    throw const _MailSetupException(
      'Incoming mail was verified, but iMail could not verify the outgoing SMTP server automatically. This does not prove the mailbox password is wrong. Review the SMTP host, port, security mode and username.',
      stage: 'outgoing',
    );
  }

  void _fillManualFromAccount(MailAccount account) {
    final incoming = account.incoming.serverConfig;
    final outgoing = account.outgoing.serverConfig;
    _username.text = _email.text.trim().toLowerCase();
    _imapHost.text = incoming.hostname;
    _imapPort.text = incoming.port.toString();
    _smtpHost.text = outgoing.hostname;
    _smtpPort.text = outgoing.port.toString();
    setState(() {
      _manual = true;
      _imapSecurity = incoming.socketType;
      _smtpSecurity = outgoing.socketType;
    });
  }

  Future<void> _connectAndSave() async {
    if (!_formKey.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _status = _manual ? 'Checking incoming mail…' : 'Finding secure mail settings…';
    });

    try {
      final email = _email.text.trim().toLowerCase();
      final password = _password.text;
      final displayName = _name.text.trim();
      final accountName = displayName.isEmpty ? email : displayName;

      final MailAccount account;
      if (_manual) {
        account = _manualAccount(
          email: email,
          password: password,
          displayName: displayName,
          accountName: accountName,
        );
        _setStatus('Checking incoming mail…');
        await _verifyIncoming(account);
        _setStatus('Checking outgoing mail…');
        await _verifyOutgoing(account);
      } else {
        account = await _automaticAccount(
          email: email,
          password: password,
          displayName: displayName,
          accountName: accountName,
        );
      }

      await ExternalAccountStore().saveAccount(account);
      if (!mounted) return;
      Navigator.pop(context, account);
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() => _manual = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } on _MailSetupException catch (e) {
      if (!mounted) return;
      if (!_manual) {
        _applyDomainDefaults();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          duration: const Duration(seconds: 7),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (!_manual) _applyDomainDefaults();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'iMail could not verify the account. Review the mail-server settings below. The app has not concluded that your password is incorrect.',
          ),
          duration: Duration(seconds: 7),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '';
        });
      }
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
                                'iMail checks incoming and outgoing mail separately so a server-setting problem is not mistaken for a bad password.',
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
                      enabled: !_busy,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Your name',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _email,
                      enabled: !_busy,
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
                      enabled: !_busy,
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
                          onPressed: _busy
                              ? null
                              : () => setState(() => _obscure = !_obscure),
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
                        enabled: !_busy,
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
                        enabled: !_busy,
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
                              enabled: !_busy,
                              keyboardType: TextInputType.number,
                              decoration:
                                  const InputDecoration(labelText: 'Port'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _SecurityDropdown(
                              value: _imapSecurity,
                              enabled: !_busy,
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
                        enabled: !_busy,
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
                              enabled: !_busy,
                              keyboardType: TextInputType.number,
                              decoration:
                                  const InputDecoration(labelText: 'Port'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _SecurityDropdown(
                              value: _smtpSecurity,
                              enabled: !_busy,
                              onChanged: (value) =>
                                  setState(() => _smtpSecurity = value),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (_busy) ...[
                      const SizedBox(height: 22),
                      const LinearProgressIndicator(
                        minHeight: 3,
                        color: imailGreen,
                        backgroundColor: Color(0xFFE6ECE9),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _status,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF53645E),
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
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
                      label: Text(_busy ? 'Verifying account…' : 'Connect account'),
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
                            'External account credentials are stored only in secure storage on this device. iMail verifies IMAP and SMTP separately before saving the account.',
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
  const _SecurityDropdown({
    required this.value,
    required this.onChanged,
    required this.enabled,
  });

  final SocketType value;
  final ValueChanged<SocketType> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<SocketType>(
      value: value,
      decoration: const InputDecoration(labelText: 'Security'),
      items: const [
        DropdownMenuItem(value: SocketType.ssl, child: Text('SSL/TLS')),
        DropdownMenuItem(value: SocketType.starttls, child: Text('STARTTLS')),
      ],
      onChanged: enabled
          ? (value) {
              if (value != null) onChanged(value);
            }
          : null,
    );
  }
}

class _MailSetupException implements Exception {
  const _MailSetupException(
    this.message, {
    required this.stage,
    this.cause,
  });

  final String message;
  final String stage;
  final Object? cause;

  @override
  String toString() => message;
}
