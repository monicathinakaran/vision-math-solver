import 'package:flutter/material.dart';
import 'chat_screen.dart'; // ChatMathRenderer

class ChatHistoryView extends StatelessWidget {
  final List messages;
  final bool isHintChat;

  const ChatHistoryView({
    super.key,
    required this.messages,
    required this.isHintChat,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: messages.map((msg) {
        final isUser = msg['role'] == "user";
        final text = msg['text']?.toString() ?? "";

        if (text.isEmpty) return const SizedBox.shrink();

        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isUser
                  ? (isHintChat ? Colors.orange : const Color(0xFF5C87FF))
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: isUser
                ? Text(text, style: const TextStyle(color: Colors.white))
                : ChatMathRenderer(text: text),
          ),
        );
      }).toList(),
    );
  }
}
