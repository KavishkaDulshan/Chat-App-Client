import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../services/image_service.dart';
import '../services/auth_service.dart'; // Import the updated service

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

    // 1. Pick Image
    final File? file = await imageService.pickImage();
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
      appBar: AppBar(title: const Text("My Profile")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 60,
                  backgroundImage:
                      (user?.profilePic != null && user!.profilePic!.isNotEmpty)
                      ? NetworkImage(user.profilePic!)
                      : null,
                  child: (user?.profilePic == null || user!.profilePic!.isEmpty)
                      ? const Icon(Icons.person, size: 60)
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: CircleAvatar(
                    backgroundColor: Colors.blue,
                    radius: 20,
                    child: IconButton(
                      icon: _isUploading
                          ? const Padding(
                              padding: EdgeInsets.all(4),
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 20,
                            ),
                      onPressed: _isUploading ? null : _pickAndUploadImage,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              user?.username ?? "User",
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(user?.email ?? "", style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
