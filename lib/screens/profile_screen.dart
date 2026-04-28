// REMOVED: import 'dart:io'; <-- Caused Web Crash
import 'package:cached_network_image/cached_network_image.dart';
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

  Future<void> _pickAndUploadImage() async {
    final imageService = ImageService();
    final authService = ref.read(authServiceProvider);
    final user = ref.read(authProvider).user;

    if (user == null) return;

    // UPDATED: Now uses XFile instead of File
    final XFile? file = await imageService.pickImage();
    if (file == null) return;

    setState(() => _isUploading = true);

    // 2. Upload to Cloudinary via your Backend
    final String? imageUrl = await imageService.uploadImage(file);

    if (imageUrl != null) {
      // 3. Update User Profile in MongoDB
      final updatedUser = await authService.updateProfilePic(user.id, imageUrl);

      if (updatedUser != null) {
        // 4. Force refresh the AuthProvider state
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
        title: Text("My Profile", style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.background,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: AppTheme.textPrimary),
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
                              placeholder: (context, url) => CircleAvatar(
                                radius: 64,
                                backgroundColor: AppTheme.secondary,
                                child: const CircularProgressIndicator(strokeWidth: 2),
                              ),
                              errorWidget: (context, url, error) => CircleAvatar(
                                radius: 64,
                                backgroundColor: AppTheme.secondary,
                                child: Icon(Icons.person_outline, size: 64, color: AppTheme.textSecondary),
                              ),
                            )
                          : CircleAvatar(
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
                Text(
                  user?.username ?? "User",
                  style: AppTheme.headerStyle.copyWith(fontSize: 28),
                ),
                const SizedBox(height: 8),
                Text(
                  user?.email ?? "",
                  style: AppTheme.subTitleStyle.copyWith(fontSize: 16),
                ),
                const SizedBox(height: 48),
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
