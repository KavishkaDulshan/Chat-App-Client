import 'package:flutter/material.dart';
import '../app_theme.dart';

class MessageBubble extends StatelessWidget {
  final String sender;
  final String text;
  final String time;
  final bool isMe;
  final String type;
  final String status; // NEW: 'sent', 'delivered', 'read'

  const MessageBubble({
    super.key,
    required this.sender,
    required this.text,
    required this.time,
    required this.isMe,
    this.type = 'text',
    this.status = 'sent', // Default
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
            // Sender Name (if not me)
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

            // Bubble
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
              child: type == 'image'
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        text,
                        height: 150,
                        width: 200,
                        fit: BoxFit.cover,
                      ),
                    )
                  : Text(
                      text,
                      style: TextStyle(
                        color: isMe ? Colors.white : AppTheme.textPrimary,
                        fontSize: 15,
                      ),
                    ),
            ),

            // Time & Ticks Row
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    time,
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                  ),

                  // TICKS LOGIC (Only for me)
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    Icon(
                      status == 'sent'
                          ? Icons.check
                          : Icons.done_all, // Single or Double
                      size: 14,
                      color: status == 'read'
                          ? Colors.blue
                          : Colors.grey, // Blue if read
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
