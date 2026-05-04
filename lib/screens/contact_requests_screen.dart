import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app_theme.dart';
import '../providers/contact_provider.dart';
import '../models/contact_request.dart';

class ContactRequestsScreen extends ConsumerStatefulWidget {
  const ContactRequestsScreen({super.key});

  @override
  ConsumerState<ContactRequestsScreen> createState() =>
      _ContactRequestsScreenState();
}

class _ContactRequestsScreenState extends ConsumerState<ContactRequestsScreen> {
  @override
  Widget build(BuildContext context) {
    final contactState = ref.watch(contactProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text(
            'Contact Requests',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          backgroundColor: AppTheme.background,
          elevation: 0,
          iconTheme: const IconThemeData(color: AppTheme.textPrimary),
          bottom: const TabBar(
            labelColor: AppTheme.primary,
            unselectedLabelColor: AppTheme.textSecondary,
            indicatorColor: AppTheme.primary,
            tabs: [
              Tab(text: 'Received'),
              Tab(text: 'Sent'),
            ],
          ),
        ),
        body: contactState.isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildList(contactState.incomingRequests, true),
                  _buildList(contactState.outgoingRequests, false),
                ],
              ),
      ),
    );
  }

  Widget _buildList(List<ContactRequest> requests, bool isIncoming) {
    if (requests.isEmpty) {
      return _buildEmptyState(isIncoming);
    }
    return RefreshIndicator(
      onRefresh: () => ref.read(contactProvider.notifier).loadPendingRequests(),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        itemCount: requests.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final req = requests[index];
          return _buildRequestTile(req, isIncoming);
        },
      ),
    );
  }

  Widget _buildEmptyState(bool isIncoming) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isIncoming ? Icons.person_add_alt_1_outlined : Icons.send_outlined,
              size: 56,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isIncoming ? 'No pending requests' : 'No sent requests',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isIncoming
                ? 'When someone sends you a contact\nrequest, it will appear here.'
                : 'Pending requests you have sent\nwill appear here.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestTile(ContactRequest req, bool isIncoming) {
    final name = isIncoming ? (req.fromUsername ?? 'Unknown') : (req.toUsername ?? 'Unknown');
    final avatar = isIncoming ? req.fromAvatar : req.toAvatar;
    final isOnline = isIncoming ? (req.fromIsOnline ?? false) : (req.toIsOnline ?? false);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Avatar
            Stack(
              children: [
                _buildAvatar(avatar, name),
                if (isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isIncoming ? 'Wants to connect with you' : 'Waiting for approval',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Action buttons
            isIncoming
                ? _AcceptDeclineButtons(req: req)
                : _CancelButton(req: req),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(String? url, String name) {
    if (url == null || url.isEmpty) {
      return CircleAvatar(
        radius: 26,
        backgroundColor: AppTheme.primary.withOpacity(0.12),
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
            color: AppTheme.primary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      imageBuilder: (_, ip) => CircleAvatar(radius: 26, backgroundImage: ip),
      placeholder: (_, __) => CircleAvatar(
        radius: 26,
        backgroundColor: AppTheme.secondary,
      ),
      errorWidget: (_, __, ___) => CircleAvatar(
        radius: 26,
        backgroundColor: AppTheme.primary.withOpacity(0.12),
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
            color: AppTheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _CancelButton extends ConsumerStatefulWidget {
  final ContactRequest req;
  const _CancelButton({required this.req});

  @override
  ConsumerState<_CancelButton> createState() => _CancelButtonState();
}

class _CancelButtonState extends ConsumerState<_CancelButton> {
  bool _isLoading = false;

  Future<void> _cancel() async {
    setState(() => _isLoading = true);
    await ref
        .read(contactProvider.notifier)
        .declineRequest(widget.req.id, widget.req.toUserId ?? '');
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return GestureDetector(
      onTap: _cancel,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: const Text(
          'Cancel',
          style: TextStyle(
            color: Colors.redAccent,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _AcceptDeclineButtons extends ConsumerStatefulWidget {
  final ContactRequest req;
  const _AcceptDeclineButtons({required this.req});

  @override
  ConsumerState<_AcceptDeclineButtons> createState() =>
      _AcceptDeclineButtonsState();
}

class _AcceptDeclineButtonsState extends ConsumerState<_AcceptDeclineButtons> {
  bool _isLoading = false;

  Future<void> _accept() async {
    setState(() => _isLoading = true);
    final ok = await ref
        .read(contactProvider.notifier)
        .acceptRequest(widget.req.id, widget.req.fromUserId ?? '');
    if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? '${widget.req.fromUsername} is now your contact!'
              : 'Failed to accept. Try again.'),
          backgroundColor: ok ? Colors.green : Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _decline() async {
    setState(() => _isLoading = true);
    await ref
        .read(contactProvider.notifier)
        .declineRequest(widget.req.id, widget.req.fromUserId ?? '');
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Decline
        GestureDetector(
          onTap: _decline,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: const Icon(Icons.close, color: Colors.redAccent, size: 18),
          ),
        ),
        const SizedBox(width: 8),
        // Accept
        GestureDetector(
          onTap: _accept,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.check, color: Colors.white, size: 18),
          ),
        ),
      ],
    );
  }
}
