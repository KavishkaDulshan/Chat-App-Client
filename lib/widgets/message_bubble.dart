import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../screens/full_screen_image.dart'; // <--- 1. ADD THIS IMPORT

class MessageBubble extends StatelessWidget {
  // ... (Your existing variables: sender, text, time, etc. keep them same)
  final String sender;
  final String text;
  final String time;
  final bool isMe;
  final String type;
  final String status;

  const MessageBubble({
    super.key,
    required this.sender,
    required this.text,
    required this.time,
    required this.isMe,
    this.type = 'text',
    this.status = 'sent',
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 4),
                child: Text(
                  sender,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                  ),
                ),
              ),

            // Bubble Container
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isMe
                    ? AppTheme.myMessageColor
                    : AppTheme.otherMessageColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: isMe
                      ? const Radius.circular(20)
                      : const Radius.circular(4),
                  bottomRight: isMe
                      ? const Radius.circular(4)
                      : const Radius.circular(20),
                ),
              ),
              // --- 2. THE FIX STARTS HERE ---
              child: type == 'image'
                  ? GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                FullScreenImage(imageUrl: text),
                          ),
                        );
                      },
                      child: Hero(
                        tag: text, // Unique tag for animation (using URL)
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            text, // This is your image URL
                            height: 150,
                            width: 200,
                            fit: BoxFit.cover, // Keep thumbnail cropped nicely
                            loadingBuilder: (ctx, child, progress) {
                              if (progress == null) return child;
                              return SizedBox(
                                height: 150,
                                width: 200,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: isMe
                                        ? Colors.white
                                        : AppTheme.primary,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    )
                  : Text(
                      // Standard Text Message
                      text,
                      style: TextStyle(
                        color: isMe ? Colors.white : AppTheme.textPrimary,
                        fontSize: 15,
                      ),
                    ),
              // --- FIX ENDS HERE ---
            ),

            // Time & Ticks logic (Keep exactly as it was)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    time,
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    Icon(
                      status == 'sent' ? Icons.check : Icons.done_all,
                      size: 14,
                      color: status == 'read' ? Colors.blue : Colors.grey,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
