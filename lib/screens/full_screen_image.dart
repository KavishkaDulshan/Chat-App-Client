import 'package:flutter/material.dart';

class FullScreenImage extends StatelessWidget {
  final String imageUrl;

  const FullScreenImage({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Dark background for immersive view
      // Transparent AppBar allows backing out easily
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      // Extend body behind app bar to use full screen
      extendBodyBehindAppBar: true,
      body: Center(
        child: InteractiveViewer(
          panEnabled: true, // Allow user to drag around when zoomed in
          boundaryMargin: const EdgeInsets.all(20),
          minScale: 0.5,
          maxScale: 4.0, // Allow zooming up to 4x
          child: Hero(
            // Key concept: This tag MUST match the tag in MessageBubble
            tag: imageUrl,
            child: Image.network(
              imageUrl,
              fit: BoxFit.contain, // Ensures the whole image is visible
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              },
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.broken_image, color: Colors.white, size: 50),
            ),
          ),
        ),
      ),
    );
  }
}
