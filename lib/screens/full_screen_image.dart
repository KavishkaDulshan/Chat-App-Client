import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart'; // Import the new package

class FullScreenImage extends StatelessWidget {
  final String imageUrl;

  const FullScreenImage({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. The Professional Image Viewer
          PhotoView(
            imageProvider: NetworkImage(imageUrl),

            // Fixes the "Black Bars" crop issue by allowing the image
            // to cover the full screen when zoomed.
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 2.5,

            // Connects the Hero animation (must match the tag in MessageBubble)
            heroAttributes: PhotoViewHeroAttributes(tag: imageUrl),

            // Shows a spinner while the HD image loads
            loadingBuilder: (context, event) => const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),

            // Handles broken links gracefully
            errorBuilder: (context, error, stackTrace) => const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image, color: Colors.grey, size: 50),
                  SizedBox(height: 8),
                  Text(
                    "Could not load image",
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),

          // 2. The "Back" Button (Top Left)
          Positioned(
            top: 40,
            left: 20,
            child: CircleAvatar(
              backgroundColor: Colors.black.withOpacity(0.5),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
