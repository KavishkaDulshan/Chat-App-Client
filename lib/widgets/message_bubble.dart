import 'package:flutter/material.dart';

class MessageBubble extends StatelessWidget {
  final String sender;
  final String text; // This holds the Message Content (Text OR Image URL)
  final String time;
  final bool isMe;
  final String type; // NEW: 'text' or 'image'

  const MessageBubble({
    super.key,
    required this.sender,
    required this.text,
    required this.time,
    required this.isMe,
    this.type = 'text', // Default to text if missing
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isMe ? const Color(0xFF007AFF) : const Color(0xFFE5E5EA),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: isMe
                  ? const Radius.circular(16)
                  : const Radius.circular(0),
              bottomRight: isMe
                  ? const Radius.circular(0)
                  : const Radius.circular(16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, // Hug content
            children: [
              // 1. SENDER NAME (Only show for others)
              if (!isMe)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4.0),
                  child: Text(
                    sender,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                ),

              // 2. CONTENT (Image OR Text)
              type == 'image'
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        text, // In this case, 'text' variable is the URL
                        fit: BoxFit.cover,
                        // Loading Spinner
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            height: 150,
                            width: 200,
                            color: Colors.black12,
                            child: Center(
                              child: CircularProgressIndicator(
                                value:
                                    loadingProgress.expectedTotalBytes != null
                                    ? loadingProgress.cumulativeBytesLoaded /
                                          loadingProgress.expectedTotalBytes!
                                    : null,
                                color: isMe ? Colors.white : Colors.blue,
                              ),
                            ),
                          );
                        },
                        // Error Icon
                        errorBuilder: (context, error, stackTrace) => Container(
                          height: 150,
                          width: 200,
                          color: Colors.grey[300],
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.broken_image, color: Colors.red),
                              Text(
                                "Failed to load",
                                style: TextStyle(fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : Text(
                      text,
                      style: TextStyle(
                        color: isMe ? Colors.white : Colors.black87,
                        fontSize: 16,
                      ),
                    ),

              // 3. TIMESTAMP
              const SizedBox(height: 5),
              Align(
                alignment: Alignment.bottomRight,
                child: Text(
                  time,
                  style: TextStyle(
                    color: isMe ? Colors.white70 : Colors.black54,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
