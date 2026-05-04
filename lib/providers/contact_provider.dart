import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/contact_request.dart';
import '../services/contact_service.dart';
import '../providers/socket_provider.dart';
import '../providers/conversations_provider.dart';

// ── State ────────────────────────────────────────────────────────────────────
class ContactState {
  final List<ContactRequest> incomingRequests;
  final List<ContactRequest> outgoingRequests;
  final bool isLoading;

  ContactState({
    this.incomingRequests = const [],
    this.outgoingRequests = const [],
    this.isLoading = false,
  });

  int get pendingCount => incomingRequests.length;

  ContactState copyWith({
    List<ContactRequest>? incomingRequests,
    List<ContactRequest>? outgoingRequests,
    bool? isLoading,
  }) {
    return ContactState(
      incomingRequests: incomingRequests ?? this.incomingRequests,
      outgoingRequests: outgoingRequests ?? this.outgoingRequests,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────
final contactProvider = NotifierProvider<ContactNotifier, ContactState>(
  ContactNotifier.new,
);

// ── Notifier ─────────────────────────────────────────────────────────────────
class ContactNotifier extends Notifier<ContactState> {
  bool _socketListening = false;

  @override
  ContactState build() {
    ref.onDispose(() {
      _removeSocketListeners();
    });
    return ContactState();
  }

  void _removeSocketListeners() {
    final socket = ref.read(socketServiceProvider).socket;
    socket.off('contact:request_received');
    socket.off('contact:request_sent');
    socket.off('contact:request_accepted');
    socket.off('contact:request_declined');
    _socketListening = false;
  }

  // Call this once the user is logged in (from HomeScreen initState)
  void init() {
    loadPendingRequests();
    _setupSocketListeners();
  }

  Future<void> loadPendingRequests() async {
    state = state.copyWith(isLoading: true);
    final requests = await ref.read(contactServiceProvider).getPendingRequests();
    state = state.copyWith(
      incomingRequests: requests['incoming'] ?? [],
      outgoingRequests: requests['outgoing'] ?? [],
      isLoading: false,
    );
  }

  void _setupSocketListeners() {
    if (_socketListening) return;
    _socketListening = true;

    final socket = ref.read(socketServiceProvider).socket;

    // We received a request
    socket.on('contact:request_received', (data) {
      final newReq = ContactRequest.fromJson(data, isIncoming: true);
      final existing = state.incomingRequests.any((r) => r.id == newReq.id);
      if (!existing) {
        state = state.copyWith(
          incomingRequests: [newReq, ...state.incomingRequests],
        );
      }
      ref.read(conversationsProvider.notifier).updateContactStatus(newReq.fromUserId ?? '', 'pending_received');
    });

    // We sent a request (server confirms)
    socket.on('contact:request_sent', (data) {
      // Refresh backend list or manually construct outgoing request
      loadPendingRequests();
      ref.read(conversationsProvider.notifier).updateContactStatus(data['toUserId']?.toString() ?? '', 'pending_sent');
    });

    // A request was accepted (either by us or by them)
    socket.on('contact:request_accepted', (data) {
      final requestId = data['requestId']?.toString() ?? '';
      final byUserId = data['byUserId']?.toString() ?? '';
      
      final updatedIncoming = state.incomingRequests.where((r) => r.id != requestId).toList();
      final updatedOutgoing = state.outgoingRequests.where((r) => r.id != requestId).toList();
      
      state = state.copyWith(
        incomingRequests: updatedIncoming,
        outgoingRequests: updatedOutgoing,
      );

      // Tell search UI we are contacts
      ref.read(conversationsProvider.notifier).updateContactStatus(byUserId, 'contacts');
      // Load chats so the new chat shows up immediately
      ref.read(conversationsProvider.notifier).loadChats();
    });

    // A request was declined or cancelled
    socket.on('contact:request_declined', (data) {
      final requestId = data['requestId']?.toString() ?? '';
      final byUserId = data['byUserId']?.toString() ?? '';
      
      final updatedIncoming = state.incomingRequests.where((r) => r.id != requestId).toList();
      final updatedOutgoing = state.outgoingRequests.where((r) => r.id != requestId).toList();
      
      state = state.copyWith(
        incomingRequests: updatedIncoming,
        outgoingRequests: updatedOutgoing,
      );

      ref.read(conversationsProvider.notifier).updateContactStatus(byUserId, 'none');
    });
  }

  Future<String> sendRequest(String toUserId) async {
    final socket = ref.read(socketServiceProvider).socket;
    socket.emit('contact:send_request', {'toUserId': toUserId});
    
    final result = await ref.read(contactServiceProvider).sendRequest(toUserId);
    if (result == null) return 'error';
    
    loadPendingRequests(); // refresh outgoing list
    return result['status']?.toString() ?? 'pending_sent';
  }

  Future<bool> acceptRequest(String requestId, String fromUserId) async {
    final socket = ref.read(socketServiceProvider).socket;
    socket.emit('contact:accept_request', {
      'requestId': requestId,
      'fromUserId': fromUserId,
    });
    
    final ok = await ref.read(contactServiceProvider).acceptRequest(requestId);
    if (ok) {
      final updated = state.incomingRequests.where((r) => r.id != requestId).toList();
      state = state.copyWith(incomingRequests: updated);
      ref.read(conversationsProvider.notifier).updateContactStatus(fromUserId, 'contacts');
      ref.read(conversationsProvider.notifier).loadChats();
    }
    return ok;
  }

  Future<bool> declineRequest(String requestId, String peerUserId) async {
    final socket = ref.read(socketServiceProvider).socket;
    socket.emit('contact:decline_request', {'requestId': requestId});
    
    final ok = await ref.read(contactServiceProvider).declineRequest(requestId);
    if (ok) {
      final inList = state.incomingRequests.where((r) => r.id != requestId).toList();
      final outList = state.outgoingRequests.where((r) => r.id != requestId).toList();
      state = state.copyWith(incomingRequests: inList, outgoingRequests: outList);
      
      ref.read(conversationsProvider.notifier).updateContactStatus(peerUserId, 'none');
    }
    return ok;
  }
}
