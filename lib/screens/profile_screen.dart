// REMOVED: import 'dart:io'; <-- Caused Web Crash
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart'; // <-- ADDED THIS
import '../providers/auth_provider.dart';
import '../services/image_service.dart';
import '../services/auth_service.dart';
import '../app_theme.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _isUploading = false;

  bool _isEditingName = false;
  bool _isSavingName = false;
  final TextEditingController _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(authProvider).user;
      if (user != null) {
        _nameController.text = user.username;
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _updateUsername() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) return;

    setState(() => _isSavingName = true);

    final authService = ref.read(authServiceProvider);
    final updatedUser = await authService.updateProfile(username: newName);

    if (updatedUser != null) {
      // Directly update the auth state with the new user data
      ref.read(authProvider.notifier).setUser(updatedUser);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Username updated successfully!")),
        );
        setState(() => _isEditingName = false);
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to update username.")),
        );
      }
    }

    setState(() => _isSavingName = false);
  }

  Future<void> _pickAndUploadImage() async {
    final imageService = ImageService();
    final authService = ref.read(authServiceProvider);
    final user = ref.read(authProvider).user;

    if (user == null) return;

    final XFile? file = await imageService.pickImage();
    if (file == null) return;

    setState(() => _isUploading = true);

    final String? imageUrl = await imageService.uploadProfileImage(file);

    if (imageUrl != null) {
      final updatedUser = await authService.updateProfile(imageUrl: imageUrl);

      if (updatedUser != null) {
        ref.read(authProvider.notifier).checkAuthStatus();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Profile updated successfully!")),
          );
        }
      }
    }

    setState(() => _isUploading = false);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text("My Profile", style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.background,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: TweenAnimationBuilder(
            duration: const Duration(milliseconds: 500),
            tween: Tween<double>(begin: 0, end: 1),
            builder: (context, double value, child) {
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 20 * (1 - value)),
                  child: child,
                ),
              );
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFE2E8F0), width: 4),
                      ),
                      child: (user?.profilePic != null && user!.profilePic!.isNotEmpty)
                          ? CachedNetworkImage(
                              imageUrl: user.profilePic!,
                              maxWidthDiskCache: 256,
                              maxHeightDiskCache: 256,
                              imageBuilder: (context, imageProvider) => CircleAvatar(
                                radius: 64,
                                backgroundImage: imageProvider,
                              ),
                              placeholder: (context, url) => const CircleAvatar(
                                radius: 64,
                                backgroundColor: AppTheme.secondary,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              errorWidget: (context, url, error) => const CircleAvatar(
                                radius: 64,
                                backgroundColor: AppTheme.secondary,
                                child: Icon(Icons.person_outline, size: 64, color: AppTheme.textSecondary),
                              ),
                            )
                          : const CircleAvatar(
                              radius: 64,
                              backgroundColor: AppTheme.secondary,
                              child: Icon(Icons.person_outline, size: 64, color: AppTheme.textSecondary),
                            ),
                    ),
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: _isUploading ? null : _pickAndUploadImage,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.background, width: 3),
                          ),
                          child: _isUploading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.camera_alt_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                if (_isEditingName)
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _nameController,
                          style: AppTheme.headerStyle.copyWith(fontSize: 24),
                          decoration: AppTheme.inputDecoration("Username").copyWith(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _isSavingName
                          ? const CircularProgressIndicator()
                          : IconButton(
                              icon: const Icon(Icons.check, color: AppTheme.primary),
                              onPressed: _updateUsername,
                            ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: () {
                          setState(() {
                            _nameController.text = user?.username ?? "User";
                            _isEditingName = false;
                          });
                        },
                      ),
                    ],
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        user?.username ?? "User",
                        style: AppTheme.headerStyle.copyWith(fontSize: 28),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20, color: AppTheme.textSecondary),
                        onPressed: () => setState(() => _isEditingName = true),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                Text(
                  user?.email ?? "",
                  style: AppTheme.subTitleStyle.copyWith(fontSize: 16),
                ),
                if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...[
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
                    ),
                    child: SwitchListTile(
                      title: const Text(
                        "Show Message Preview",
                        style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w500),
                      ),
                      subtitle: const Text(
                        "Display message content in push notifications",
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      ),
                      value: user?.showNotificationPreview ?? false,
                      activeColor: AppTheme.primary,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (value) async {
                        final updatedUser = await ref.read(authServiceProvider).updateProfile(showNotificationPreview: value);
                        if (updatedUser != null) {
                          ref.read(authProvider.notifier).setUser(updatedUser);
                        }
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.info_outline, color: AppTheme.textSecondary, size: 20),
                      const SizedBox(width: 12),
                      Text("Joined recently", style: AppTheme.subTitleStyle),
                    ],
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
