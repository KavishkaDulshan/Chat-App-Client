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

    return Scaffold(
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE2E8F0), height: 1),
        ),
      ),
      body: contactState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : contactState.pendingRequests.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: () =>
                      ref.read(contactProvider.notifier).loadPendingRequests(),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    itemCount: contactState.pendingRequests.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final req = contactState.pendingRequests[index];
                      return _buildRequestTile(req);
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
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
            child: const Icon(
              Icons.person_add_alt_1_outlined,
              size: 56,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No pending requests',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'When someone sends you a contact\nrequest, it will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestTile(ContactRequest req) {
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
                _buildAvatar(req.fromAvatar, req.fromUsername),
                if (req.fromIsOnline)
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
                    req.fromUsername,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'Wants to connect with you',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Action buttons
            _AcceptDeclineButtons(req: req),
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
        .acceptRequest(widget.req.requestId, widget.req.fromUserId);
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
        .declineRequest(widget.req.requestId);
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
