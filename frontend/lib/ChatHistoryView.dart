import 'package:flutter/material.dart';
import 'chat_screen.dart'; // ChatMathRenderer

class ChatHistoryView extends StatelessWidget {
  final List messages;
  const ChatHistoryView({super.key, required this.messages});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: messages.map((msg) {
        final isUser = msg['role'] == "user";
        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isUser ? Colors.blue : Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: isUser
              ? Text(msg['text'], style: const TextStyle(color: Colors.white))
              : ChatMathRenderer(text: msg['text']),
          ),
        );
      }).toList(),
    );
  }
}