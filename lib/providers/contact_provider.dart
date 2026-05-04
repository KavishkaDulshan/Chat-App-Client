import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/contact_request.dart';
import '../services/contact_service.dart';
import '../providers/socket_provider.dart';

// ── State ────────────────────────────────────────────────────────────────────
class ContactState {
  final List<ContactRequest> pendingRequests;
  final bool isLoading;

  ContactState({this.pendingRequests = const [], this.isLoading = false});

  int get pendingCount => pendingRequests.length;

  ContactState copyWith({List<ContactRequest>? pendingRequests, bool? isLoading}) {
    return ContactState(
      pendingRequests: pendingRequests ?? this.pendingRequests,
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
    state = state.copyWith(pendingRequests: requests, isLoading: false);
  }

  void _setupSocketListeners() {
    if (_socketListening) return;
    _socketListening = true;

    final socket = ref.read(socketServiceProvider).socket;

    // A new request arrived in real-time
    socket.on('contact:request_received', (data) {
      final newReq = ContactRequest(
        requestId: data['requestId']?.toString() ?? '',
        fromUserId: data['fromUserId']?.toString() ?? '',
        fromUsername: data['fromUsername']?.toString() ?? 'Unknown',
        fromAvatar: data['fromAvatar']?.toString(),
        fromIsOnline: data['fromIsOnline'] == true,
      );
      // Add to pending list if not already there
      final existing = state.pendingRequests.any((r) => r.requestId == newReq.requestId);
      if (!existing) {
        state = state.copyWith(
          pendingRequests: [newReq, ...state.pendingRequests],
        );
      }
    });

    // A request was accepted (either by us or by the other side)
    socket.on('contact:request_accepted', (data) {
      final requestId = data['requestId']?.toString() ?? '';
      // Remove from pending list
      final updated = state.pendingRequests
          .where((r) => r.requestId != requestId)
          .toList();
      state = state.copyWith(pendingRequests: updated);
    });

    // A request was declined
    socket.on('contact:request_declined', (data) {
      final requestId = data['requestId']?.toString() ?? '';
      final updated = state.pendingRequests
          .where((r) => r.requestId != requestId)
          .toList();
      state = state.copyWith(pendingRequests: updated);
    });
  }

  // Send a request via socket (fast path) + REST fallback
  Future<String> sendRequest(String toUserId) async {
    final socket = ref.read(socketServiceProvider).socket;
    // Optimistic: emit via socket for real-time delivery
    socket.emit('contact:send_request', {'toUserId': toUserId});
    // Also via REST for persistence if socket drops
    final result = await ref.read(contactServiceProvider).sendRequest(toUserId);
    if (result == null) return 'error';
    return result['status']?.toString() ?? 'pending_sent';
  }

  Future<bool> acceptRequest(String requestId, String fromUserId) async {
    final socket = ref.read(socketServiceProvider).socket;
    // Real-time accept
    socket.emit('contact:accept_request', {
      'requestId': requestId,
      'fromUserId': fromUserId,
    });
    // REST for persistence
    final ok = await ref.read(contactServiceProvider).acceptRequest(requestId);
    if (ok) {
      final updated = state.pendingRequests
          .where((r) => r.requestId != requestId)
          .toList();
      state = state.copyWith(pendingRequests: updated);
    }
    return ok;
  }

  Future<bool> declineRequest(String requestId) async {
    final socket = ref.read(socketServiceProvider).socket;
    socket.emit('contact:decline_request', {'requestId': requestId});
    final ok = await ref.read(contactServiceProvider).declineRequest(requestId);
    if (ok) {
      final updated = state.pendingRequests
          .where((r) => r.requestId != requestId)
          .toList();
      state = state.copyWith(pendingRequests: updated);
    }
    return ok;
  }
}
