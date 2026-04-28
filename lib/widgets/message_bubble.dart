import 'package:cached_network_image/cached_network_image.dart';
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
            _buildCachedSenderAvatar(),
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
                ClipRRect(
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: isMe
                        ? const Radius.circular(16)
                        : const Radius.circular(4),
                    bottomRight: isMe
                        ? const Radius.circular(4)
                        : const Radius.circular(16),
                  ),
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                      maxHeight: MediaQuery.of(context).size.height * 0.6,
                    ),
                    padding: type == 'image' ? EdgeInsets.zero : const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: isMe ? AppTheme.myMessageColor : AppTheme.otherMessageColor,
                      border: isMe ? null : Border.all(color: const Color(0xFFE2E8F0), width: 1),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: isMe
                            ? const Radius.circular(16)
                            : const Radius.circular(4),
                        bottomRight: isMe
                            ? const Radius.circular(4)
                            : const Radius.circular(16),
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
                            child: CachedNetworkImage(
                              imageUrl: text,
                              maxWidthDiskCache: 800,
                              maxHeightDiskCache: 800,
                              fit: BoxFit.contain,
                              placeholder: (ctx, url) => Container(
                                constraints: const BoxConstraints(
                                  minHeight: 150,
                                  minWidth: 150,
                                ),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: isMe
                                        ? Colors.white
                                        : AppTheme.primary,
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) {
                                return Container(
                                  constraints: const BoxConstraints(
                                    minHeight: 150,
                                    minWidth: 150,
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.broken_image,
                                      size: 40,
                                      color: Colors.white,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        )
                      : type == 'audio' // ✅ Check for Audio
                      ? Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: AudioBubble(
                            url: text, // 'text' field contains the Audio URL
                            isMe: isMe,
                            // If you update your DB to store duration, pass it here:
                            // duration: duration,
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          // Safety: if raw E2E ciphertext leaked through,
                          // show a lock icon instead of raw gibberish.
                          child: text.startsWith('e2e:v1:')
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.lock_outline,
                                      size: 16,
                                      color: isMe
                                          ? Colors.white70
                                          : Colors.grey,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Encrypted message',
                                      style: TextStyle(
                                        color: isMe
                                            ? Colors.white70
                                            : Colors.grey,
                                        fontSize: 14,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                )
                              : Text(
                                  text,
                                  style: TextStyle(
                                    color: isMe ? Colors.white : AppTheme.textPrimary,
                                    fontSize: 15,
                                    height: 1.4,
                                  ),
                                ),
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

  /// Cached sender avatar — persisted to disk at 96px for offline display.
  Widget _buildCachedSenderAvatar() {
    if (senderAvatar == null || senderAvatar!.isEmpty) {
      return CircleAvatar(
        radius: 16,
        backgroundColor: Colors.grey[300],
        child: Text(
          sender.isNotEmpty ? sender[0].toUpperCase() : "?",
          style: const TextStyle(fontSize: 12, color: Colors.black),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: senderAvatar!,
      maxWidthDiskCache: 96,
      maxHeightDiskCache: 96,
      memCacheWidth: 32,
      memCacheHeight: 32,
      imageBuilder: (context, imageProvider) => CircleAvatar(
        radius: 16,
        backgroundImage: imageProvider,
      ),
      placeholder: (context, url) => CircleAvatar(
        radius: 16,
        backgroundColor: Colors.grey[300],
      ),
      errorWidget: (context, url, error) => CircleAvatar(
        radius: 16,
        backgroundColor: Colors.grey[300],
        child: Text(
          sender.isNotEmpty ? sender[0].toUpperCase() : "?",
          style: const TextStyle(fontSize: 12, color: Colors.black),
        ),
      ),
    );
  }
}
