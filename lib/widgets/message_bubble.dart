import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../screens/full_screen_image.dart';
import 'audio_bubble.dart'; // ✅ Import the AudioBubble widget

class MessageBubble extends StatelessWidget {
  final String sender;
  final String? senderAvatar;
  final String text;
  final String time;
  final bool isMe;
  final String type;
  final String status;
  // Note: If you add 'duration' to your message model later, pass it here too.

  const MessageBubble({
    super.key,
    required this.sender,
    this.senderAvatar,
    required this.text,
    required this.time,
    required this.isMe,
    this.type = 'text',
    this.status = 'sent',
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 1. SHOW AVATAR (Only for other users)
          if (!isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.grey[300],
              backgroundImage:
                  (senderAvatar != null && senderAvatar!.isNotEmpty)
                  ? NetworkImage(senderAvatar!)
                  : null,
              child: (senderAvatar == null || senderAvatar!.isEmpty)
                  ? Text(
                      sender.isNotEmpty ? sender[0].toUpperCase() : "?",
                      style: const TextStyle(fontSize: 12, color: Colors.black),
                    )
                  : null,
            ),
            const SizedBox(width: 8),
          ],

          // 2. MESSAGE CONTENT
          Flexible(
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                // Sender Name (Only if not me)
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 4),
                    child: Text(
                      sender,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),

                // The Bubble
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isMe ? AppTheme.primary : Colors.grey[200],
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: isMe
                          ? const Radius.circular(20)
                          : Radius.zero,
                      bottomRight: isMe
                          ? Radius.zero
                          : const Radius.circular(20),
                    ),
                  ),
                  // ✅ UPDATED LOGIC HERE
                  child: type == 'image'
                      ? GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FullScreenImage(imageUrl: text),
                              ),
                            );
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              text,
                              height: 200,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              loadingBuilder: (ctx, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return SizedBox(
                                  height: 200,
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      value:
                                          loadingProgress.expectedTotalBytes !=
                                              null
                                          ? loadingProgress
                                                    .cumulativeBytesLoaded /
                                                loadingProgress
                                                    .expectedTotalBytes!
                                          : null,
                                      color: isMe
                                          ? Colors.white
                                          : AppTheme.primary,
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return const SizedBox(
                                  height: 200,
                                  child: Center(
                                    child: Icon(
                                      Icons.broken_image,
                                      color: Colors.white,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        )
                      : type ==
                            'audio' // ✅ Check for Audio
                      ? AudioBubble(
                          url: text, // 'text' field contains the Audio URL
                          isMe: isMe,
                          // If you update your DB to store duration, pass it here:
                          // duration: duration,
                        )
                      : Text(
                          text,
                          style: TextStyle(
                            color: isMe ? Colors.white : Colors.black87,
                            fontSize: 15,
                          ),
                        ),
                ),

                // Time & Status
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
        ],
      ),
    );
  }
}
