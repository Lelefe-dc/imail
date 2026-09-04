import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'api_client.dart';
import 'models.dart';

enum MailCommandKind {
  bootstrap,
  login,
  refresh,
  selectFolder,
  search,
  openMessage,
  toggleStar,
  markUnread,
  markAnswered,
  delete,
  move,
  logout,
  silentSync,
  send,
  saveDraft,
  downloadAttachment,
  appVisibility,
}

class MailSendPayload {
  const MailSendPayload({
    required this.to,
    required this.cc,
    required this.bcc,
    required this.subject,
    required this.bodyText,
    required this.attachments,
    required this.inReplyTo,
    required this.references,
  });

  final List<String> to;
  final List<String> cc;
  final List<String> bcc;
  final String subject;
  final String bodyText;
  final List<MailUploadAttachment> attachments;
  final String inReplyTo;
  final String references;
}

class MailDraftPayload {
  const MailDraftPayload({
    required this.to,
    required this.cc,
    required this.subject,
    required this.bodyText,
  });

  final List<String> to;
  final List<String> cc;
  final String subject;
  final String bodyText;
}

class MailAttachmentRequest {
  const MailAttachmentRequest({
    required this.uid,
    required this.index,
    required this.folder,
  });

  final String uid;
  final int index;
  final String folder;
}

class MailCommand {
  const MailCommand(
    this.kind, {
    this.completion,
    this.email,
    this.password,
    this.folder,
    this.query,
    this.message,
    this.destination,
    this.active,
    this.forceMessages = false,
    this.sendPayload,
    this.draftPayload,
    this.attachmentRequest,
  });

  final MailCommandKind kind;
  final Completer<Object?>? completion;
  final String? email;
  final String? password;
  final String? folder;
  final String? query;
  final MailMessage? message;
  final String? destination;
  final bool? active;
  final bool forceMessages;
  final MailSendPayload? sendPayload;
  final MailDraftPayload? draftPayload;
  final MailAttachmentRequest? attachmentRequest;
}

/// Serial event BLoC for mailbox reads and mutations. The UI still consumes
/// MailStore as a ChangeNotifier, while every server operation is queued here
/// so refreshes, incoming checks and optimistic mutations cannot race.
class MailEventBloc extends Bloc<MailCommand, int> {
  MailEventBloc(this.owner) : super(0) {
    on<MailCommand>(_onCommand);
  }

  final MailStore owner;
  Future<void> _tail = Future<void>.value();
  Timer? _pollTimer;
  bool _active = true;

  static const int _configuredPollSeconds = int.fromEnvironment(
    'IMAIL_MAIL_POLL_SECONDS',
    defaultValue: 12,
  );

  Future<void> _onCommand(MailCommand event, Emitter<int> emit) async {
    final operation = _tail.then((_) => _execute(event, emit));
    _tail = operation.then<void>((_) {}, onError: (_, __) {});
    await operation;
  }

  Future<void> _execute(MailCommand event, Emitter<int> emit) async {
    Object? result;
    try {
      switch (event.kind) {
        case MailCommandKind.bootstrap:
          await owner._performBootstrap();
          break;
        case MailCommandKind.login:
          await owner._performLogin(event.email ?? '', event.password ?? '');
          break;
        case MailCommandKind.refresh:
          await owner._performRefresh(showBusy: true);
          break;
        case MailCommandKind.selectFolder:
          await owner._performSelectFolder(event.folder ?? 'INBOX');
          break;
        case MailCommandKind.search:
          await owner._performSearch(event.query ?? '');
          break;
        case MailCommandKind.openMessage:
          result = await owner._performOpenMessage(event.message!);
          break;
        case MailCommandKind.toggleStar:
          await owner._performToggleStar(event.message!);
          break;
        case MailCommandKind.markUnread:
          await owner._performMarkUnread(event.message!);
          break;
        case MailCommandKind.markAnswered:
          await owner._performMarkAnswered(event.message!);
          break;
        case MailCommandKind.delete:
          await owner._performDelete(event.message!);
          break;
        case MailCommandKind.move:
          await owner._performMove(event.message!, event.destination ?? 'INBOX');
          break;
        case MailCommandKind.logout:
          await owner._performLogout();
          break;
        case MailCommandKind.silentSync:
          await owner._performSilentSync(forceMessages: event.forceMessages);
          break;
        case MailCommandKind.send:
          await owner._performSend(event.sendPayload!);
          break;
        case MailCommandKind.saveDraft:
          await owner._performSaveDraft(event.draftPayload!);
          break;
        case MailCommandKind.downloadAttachment:
          final request = event.attachmentRequest!;
          result = await owner._api.downloadAttachment(
            request.uid,
            request.index,
            folder: request.folder,
          );
          break;
        case MailCommandKind.appVisibility:
          _active = event.active ?? true;
          if (_active && owner.authenticated) {
            _startPolling();
            add(const MailCommand(
              MailCommandKind.silentSync,
              forceMessages: true,
            ));
          } else {
            _stopPolling();
          }
          break;
      }

      if (owner.authenticated && _active) {
        _startPolling();
      } else if (!owner.authenticated) {
        _stopPolling();
      }
      emit(state + 1);
      event.completion?.complete(result);
    } catch (error, stackTrace) {
      if (!(event.completion?.isCompleted ?? true)) {
        event.completion!.completeError(error, stackTrace);
      }
      emit(state + 1);
    }
  }

  void _startPolling() {
    if (_pollTimer != null || !_active || !owner.authenticated) return;
    final seconds = _configuredPollSeconds < 5 ? 5 : _configuredPollSeconds;
    _pollTimer = Timer.periodic(Duration(seconds: seconds), (_) {
      if (!isClosed && _active && owner.authenticated) {
        add(const MailCommand(MailCommandKind.silentSync));
      }
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  Future<void> close() {
    _stopPolling();
    return super.close();
  }
}

class MailMutationGateway {
  const MailMutationGateway(this._store);
  final MailStore _store;

  Future<void> send({
    required List<String> to,
    List<String> cc = const [],
    List<String> bcc = const [],
    String subject = '',
    String bodyText = '',
    List<MailUploadAttachment> attachments = const [],
    String inReplyTo = '',
    String references = '',
  }) =>
      _store._sendMessage(
        MailSendPayload(
          to: to,
          cc: cc,
          bcc: bcc,
          subject: subject,
          bodyText: bodyText,
          attachments: attachments,
          inReplyTo: inReplyTo,
          references: references,
        ),
      );

  Future<void> saveDraft({
    List<String> to = const [],
    List<String> cc = const [],
    String subject = '',
    String bodyText = '',
  }) =>
      _store._saveDraftMessage(
        MailDraftPayload(
          to: to,
          cc: cc,
          subject: subject,
          bodyText: bodyText,
        ),
      );

  Future<Uint8List> downloadAttachment(
    String uid,
    int index, {
    required String folder,
  }) =>
      _store._downloadAttachment(uid, index, folder: folder);
}

class MailStore extends ChangeNotifier with WidgetsBindingObserver {
  MailStore(IMailApiClient apiClient) : _api = apiClient {
    api = MailMutationGateway(this);
    _events = MailEventBloc(this);
    WidgetsBinding.instance.addObserver(this);
  }

  final IMailApiClient _api;
  late final MailMutationGateway api;
  late final MailEventBloc _events;

  bool booting = true;
  bool busy = false;
  String? error;
  String? address;
  String displayName = '';
  String selectedFolder = 'INBOX';
  String query = '';
  List<MailFolder> folders = const [];
  List<MailMessage> messages = const [];
  DateTime? lastSyncedAt;
  int incomingRevision = 0;

  bool _syncing = false;
  int _pollSequence = 0;

  bool get authenticated => address != null && address!.isNotEmpty;

  Future<Object?> _dispatch(
    MailCommandKind kind, {
    String? email,
    String? password,
    String? folder,
    String? query,
    MailMessage? message,
    String? destination,
    bool forceMessages = false,
    MailSendPayload? sendPayload,
    MailDraftPayload? draftPayload,
    MailAttachmentRequest? attachmentRequest,
  }) {
    final completion = Completer<Object?>();
    _events.add(
      MailCommand(
        kind,
        completion: completion,
        email: email,
        password: password,
        folder: folder,
        query: query,
        message: message,
        destination: destination,
        forceMessages: forceMessages,
        sendPayload: sendPayload,
        draftPayload: draftPayload,
        attachmentRequest: attachmentRequest,
      ),
    );
    return completion.future;
  }

  Future<void> bootstrap() async {
    await _dispatch(MailCommandKind.bootstrap);
  }

  Future<void> login(String email, String password) async {
    await _dispatch(
      MailCommandKind.login,
      email: email,
      password: password,
    );
  }

  Future<void> refresh() async {
    await _dispatch(MailCommandKind.refresh);
  }

  Future<void> selectFolder(String folder) async {
    await _dispatch(MailCommandKind.selectFolder, folder: folder);
  }

  Future<void> search(String value) async {
    await _dispatch(MailCommandKind.search, query: value);
  }

  Future<MailMessage> openMessage(MailMessage item) async {
    final value = await _dispatch(MailCommandKind.openMessage, message: item);
    return value as MailMessage;
  }

  Future<void> toggleStar(MailMessage item) async {
    await _dispatch(MailCommandKind.toggleStar, message: item);
  }

  Future<void> markUnread(MailMessage item) async {
    await _dispatch(MailCommandKind.markUnread, message: item);
  }

  Future<void> markAnswered(MailMessage item) async {
    await _dispatch(MailCommandKind.markAnswered, message: item);
  }

  Future<void> delete(MailMessage item) async {
    await _dispatch(MailCommandKind.delete, message: item);
  }

  Future<void> move(MailMessage item, String destination) async {
    await _dispatch(
      MailCommandKind.move,
      message: item,
      destination: destination,
    );
  }

  Future<void> logout() async {
    await _dispatch(MailCommandKind.logout);
  }

  Future<void> _sendMessage(MailSendPayload payload) async {
    await _dispatch(MailCommandKind.send, sendPayload: payload);
  }

  Future<void> _saveDraftMessage(MailDraftPayload payload) async {
    await _dispatch(MailCommandKind.saveDraft, draftPayload: payload);
  }

  Future<Uint8List> _downloadAttachment(
    String uid,
    int index, {
    required String folder,
  }) async {
    final value = await _dispatch(
      MailCommandKind.downloadAttachment,
      attachmentRequest: MailAttachmentRequest(
        uid: uid,
        index: index,
        folder: folder,
      ),
    );
    return value as Uint8List;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (!_events.isClosed) {
      _events.add(MailCommand(MailCommandKind.appVisibility, active: active));
    }
  }

  Future<void> _performBootstrap() async {
    booting = true;
    error = null;
    notifyListeners();

    final hasSession = await _api.restoreCookie();
    if (!hasSession) {
      booting = false;
      notifyListeners();
      return;
    }

    // Paint the mailbox shell immediately from the cached account instead of
    // holding the user on a blank/launch screen while network calls complete.
    final cached = _api.cachedAddress;
    if (cached != null && cached.isNotEmpty) {
      address = cached;
      booting = false;
      busy = true;
      notifyListeners();
    }

    try {
      final restored = await _api.sessionAddress().timeout(
            const Duration(seconds: 7),
          );
      if (restored.isEmpty) {
        await _expireSession();
        return;
      }
      address = restored;
      booting = false;
      busy = true;
      notifyListeners();
      await _loadMailbox();
    } on TimeoutException {
      // Keep the cached account visible and let the foreground listener retry.
      error = 'Mail is taking longer than usual to connect. Retrying…';
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await _expireSession();
      } else {
        error = e.message;
      }
    } finally {
      booting = false;
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _performLogin(String email, String password) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      address = await _api.login(email, password);
      selectedFolder = 'INBOX';
      query = '';
      notifyListeners();
      await _loadMailbox();
    } on ApiException catch (e) {
      error = e.message;
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _loadMailbox() async {
    final results = await Future.wait<dynamic>([
      _api.folders(),
      _api.messages(folder: selectedFolder, query: query),
      _api.identity(),
    ]);
    folders = results[0] as List<MailFolder>;
    messages = results[1] as List<MailMessage>;
    final identity = results[2] as Map<String, String>;
    displayName = identity['display_name'] ?? '';
    if (identity['address']?.isNotEmpty == true) {
      address = identity['address'];
    }
    lastSyncedAt = DateTime.now();
    incomingRevision++;
    notifyListeners();
  }

  Future<void> _performRefresh({required bool showBusy}) async {
    if (showBusy) {
      busy = true;
      error = null;
      notifyListeners();
    }
    try {
      final results = await Future.wait<dynamic>([
        _api.folders(),
        _api.messages(folder: selectedFolder, query: query),
      ]);
      folders = results[0] as List<MailFolder>;
      messages = results[1] as List<MailMessage>;
      lastSyncedAt = DateTime.now();
      incomingRevision++;
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await _expireSession();
      } else {
        error = e.message;
      }
    } finally {
      if (showBusy) busy = false;
      notifyListeners();
    }
  }

  Future<void> _performSilentSync({bool forceMessages = false}) async {
    if (!authenticated || _syncing) return;
    _syncing = true;
    try {
      final oldFolders = folders;
      final freshFolders = await _api.folders();
      final oldFingerprint = _folderFingerprint(oldFolders);
      final newFingerprint = _folderFingerprint(freshFolders);
      final selectedChanged = _selectedFolderChanged(oldFolders, freshFolders);
      final folderChanged = oldFingerprint != newFingerprint;

      _pollSequence++;
      final refreshMessages = forceMessages ||
          selectedChanged ||
          query.isNotEmpty ||
          _pollSequence % 4 == 0;

      List<MailMessage>? freshMessages;
      if (refreshMessages) {
        freshMessages = await _api.messages(
          folder: selectedFolder,
          query: query,
        );
      }

      final messageChanged = freshMessages != null &&
          _messageFingerprint(messages) != _messageFingerprint(freshMessages);
      if (folderChanged || messageChanged) {
        folders = freshFolders;
        if (freshMessages != null) messages = freshMessages;
        incomingRevision++;
        notifyListeners();
      }
      lastSyncedAt = DateTime.now();
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await _expireSession();
      }
      // Background checks stay quiet for ordinary network failures.
    } finally {
      _syncing = false;
    }
  }

  Future<void> _performSelectFolder(String folder) async {
    selectedFolder = folder;
    query = '';
    messages = const [];
    busy = true;
    notifyListeners();
    await _performRefresh(showBusy: false);
    busy = false;
    notifyListeners();
  }

  Future<void> _performSearch(String value) async {
    query = value.trim();
    await _performRefresh(showBusy: true);
  }

  Future<MailMessage> _performOpenMessage(MailMessage item) async {
    final detailed = await _api.message(item.uid, folder: selectedFolder);
    if (!item.seen && detailed.seen) {
      _adjustFolder(selectedFolder, unreadDelta: -1, create: false);
    }
    _replaceMessage(detailed, notify: false);
    notifyListeners();
    return detailed;
  }

  Future<void> _performToggleStar(MailMessage item) async {
    final snapshot = messages;
    _replaceMessage(item.copyWith(flagged: !item.flagged));
    try {
      final updated = await _api.setFlags(
        item.uid,
        folder: selectedFolder,
        flagged: !item.flagged,
      );
      _replaceMessage(updated);
    } on ApiException catch (e) {
      messages = snapshot;
      error = e.message;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _performMarkUnread(MailMessage item) async {
    final snapshotMessages = messages;
    final snapshotFolders = folders;
    if (item.seen) {
      _replaceMessage(item.copyWith(seen: false), notify: false);
      _adjustFolder(selectedFolder, unreadDelta: 1, create: false);
      notifyListeners();
    }
    try {
      final updated = await _api.setFlags(
        item.uid,
        folder: selectedFolder,
        seen: false,
      );
      _replaceMessage(updated);
    } on ApiException catch (e) {
      messages = snapshotMessages;
      folders = snapshotFolders;
      error = e.message;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _performMarkAnswered(MailMessage item) async {
    final snapshot = messages;
    _replaceMessage(item.copyWith(answered: true));
    try {
      final updated = await _api.setFlags(
        item.uid,
        folder: selectedFolder,
        answered: true,
      );
      _replaceMessage(updated);
    } on ApiException {
      // Sending has already succeeded. Reconcile the answered flag later.
      messages = snapshot;
      notifyListeners();
    }
  }

  Future<void> _performDelete(MailMessage item) async {
    final snapshotMessages = messages;
    final snapshotFolders = folders;
    final source = selectedFolder;
    final sourceIsTrash = _isTrash(source);

    messages = messages.where((message) => message.uid != item.uid).toList();
    _adjustFolder(
      source,
      totalDelta: -1,
      unreadDelta: item.seen ? 0 : -1,
      create: false,
    );
    if (!sourceIsTrash) {
      _adjustFolder(
        _existingFolderName('Trash') ?? 'Trash',
        totalDelta: 1,
        unreadDelta: item.seen ? 0 : 1,
      );
    }
    notifyListeners();

    try {
      await _api.deleteMessage(item.uid, folder: source);
      unawaited(_queueSilentReconcile(forceMessages: false));
    } on ApiException catch (e) {
      messages = snapshotMessages;
      folders = snapshotFolders;
      error = e.message;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _performMove(MailMessage item, String destination) async {
    final source = selectedFolder;
    if (source.toLowerCase() == destination.toLowerCase()) return;

    final snapshotMessages = messages;
    final snapshotFolders = folders;
    messages = messages.where((message) => message.uid != item.uid).toList();
    _adjustFolder(
      source,
      totalDelta: -1,
      unreadDelta: item.seen ? 0 : -1,
      create: false,
    );
    _adjustFolder(
      destination,
      totalDelta: 1,
      unreadDelta: item.seen ? 0 : 1,
    );
    notifyListeners();

    try {
      await _api.moveMessage(
        item.uid,
        folder: source,
        destination: destination,
      );
      unawaited(_queueSilentReconcile(forceMessages: false));
    } on ApiException catch (e) {
      messages = snapshotMessages;
      folders = snapshotFolders;
      error = e.message;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _performSend(MailSendPayload payload) async {
    await _api.send(
      to: payload.to,
      cc: payload.cc,
      bcc: payload.bcc,
      subject: payload.subject,
      bodyText: payload.bodyText,
      attachments: payload.attachments,
      inReplyTo: payload.inReplyTo,
      references: payload.references,
    );
    final sentName = _existingFolderName('Sent') ?? 'Sent';
    _adjustFolder(sentName, totalDelta: 1);
    notifyListeners();
    await _performSilentSync(
      forceMessages: selectedFolder.toLowerCase() == sentName.toLowerCase(),
    );
  }

  Future<void> _performSaveDraft(MailDraftPayload payload) async {
    await _api.saveDraft(
      to: payload.to,
      cc: payload.cc,
      subject: payload.subject,
      bodyText: payload.bodyText,
    );
    final draftsName = _existingFolderName('Drafts') ?? 'Drafts';
    _adjustFolder(draftsName, totalDelta: 1);
    notifyListeners();
    await _performSilentSync(
      forceMessages: selectedFolder.toLowerCase() == draftsName.toLowerCase(),
    );
  }

  Future<void> _performLogout() async {
    busy = true;
    notifyListeners();
    try {
      await _api.logout();
    } finally {
      _resetMailbox();
      booting = false;
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _expireSession() async {
    await _api.clearLocalSession();
    _resetMailbox();
    booting = false;
    busy = false;
    notifyListeners();
  }

  void _resetMailbox() {
    address = null;
    displayName = '';
    selectedFolder = 'INBOX';
    query = '';
    folders = const [];
    messages = const [];
    lastSyncedAt = null;
  }

  void _replaceMessage(MailMessage item, {bool notify = true}) {
    final index = messages.indexWhere((message) => message.uid == item.uid);
    if (index < 0) return;
    final copy = [...messages];
    copy[index] = item;
    messages = copy;
    if (notify) notifyListeners();
  }

  void _adjustFolder(
    String name, {
    int totalDelta = 0,
    int unreadDelta = 0,
    bool create = true,
  }) {
    final index = folders.indexWhere(
      (folder) => folder.name.toLowerCase() == name.toLowerCase(),
    );
    if (index < 0) {
      if (!create) return;
      folders = [
        ...folders,
        MailFolder(
          name,
          totalCount: math.max(0, totalDelta),
          unreadCount: math.max(0, unreadDelta),
        ),
      ];
      return;
    }

    final folder = folders[index];
    final copy = [...folders];
    copy[index] = folder.copyWith(
      totalCount: math.max(0, folder.totalCount + totalDelta),
      unreadCount: math.max(0, folder.unreadCount + unreadDelta),
    );
    folders = copy;
  }

  String? _existingFolderName(String wanted) {
    final direct = folders.where(
      (folder) => folder.name.toLowerCase() == wanted.toLowerCase(),
    );
    if (direct.isNotEmpty) return direct.first.name;
    final contains = folders.where(
      (folder) => folder.name.toLowerCase().contains(wanted.toLowerCase()),
    );
    return contains.isEmpty ? null : contains.first.name;
  }

  bool _isTrash(String value) {
    final lower = value.toLowerCase();
    return lower == 'trash' ||
        lower == 'deleted' ||
        lower == 'deleted items';
  }

  String _folderFingerprint(List<MailFolder> value) =>
      value.map((folder) => folder.fingerprint).join('|');

  String _messageFingerprint(List<MailMessage> value) => value
      .map(
        (message) =>
            '${message.uid}:${message.seen}:${message.flagged}:${message.answered}:${message.draft}',
      )
      .join('|');

  bool _selectedFolderChanged(
    List<MailFolder> previous,
    List<MailFolder> current,
  ) {
    MailFolder? before;
    MailFolder? after;
    for (final folder in previous) {
      if (folder.name.toLowerCase() == selectedFolder.toLowerCase()) {
        before = folder;
        break;
      }
    }
    for (final folder in current) {
      if (folder.name.toLowerCase() == selectedFolder.toLowerCase()) {
        after = folder;
        break;
      }
    }
    if (before == null || after == null) return before != after;
    return before.totalCount != after.totalCount ||
        before.unreadCount != after.unreadCount;
  }

  Future<void> _queueSilentReconcile({required bool forceMessages}) async {
    if (_events.isClosed) return;
    _events.add(MailCommand(
      MailCommandKind.silentSync,
      forceMessages: forceMessages,
    ));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_events.close());
    super.dispose();
  }
}
