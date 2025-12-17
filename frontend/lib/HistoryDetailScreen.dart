import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'main.dart';              // for Config.baseUrl
import 'chat_screen.dart';       // for ChatMathRenderer
import 'main.dart' show MathExplanation; 
import 'ChatHistoryView.dart';

class HistoryDetailScreen extends StatefulWidget {
  final String historyId;
  const HistoryDetailScreen({super.key, required this.historyId});

  @override
  State<HistoryDetailScreen> createState() => _HistoryDetailScreenState();
}

class _HistoryDetailScreenState extends State<HistoryDetailScreen> {
  Map<String, dynamic>? data;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final res = await http.get(
      Uri.parse("${Config.baseUrl}/api/history/${widget.historyId}")
    );
    if (res.statusCode == 200) {
      setState(() {
        data = jsonDecode(res.body);
        loading = false;
      });
    }
  }

@override
Widget build(BuildContext context) {
  if (loading) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }

  final bool isHint = data!['mode_used'] == "hint";
  final List hintChat = data!['hint_chat'] ?? [];
  final List tutorChat = data!['tutor_chat'] ?? [];
  final List legacyChat = data!['chat_history'] ?? [];

return Scaffold(
  backgroundColor: const Color(0xFFF5F7FA), // soft app background
  appBar: AppBar(
    title: const Text("History Detail"),
    backgroundColor: Colors.white,
    foregroundColor: Colors.black87,
    elevation: 1,
  ),
  body: SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [

        /// 1️⃣ FINAL OCR / EDITED PROBLEM
        Card(
          color: Colors.white,
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              data!['equation'],
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ),

        const SizedBox(height: 20),

        /// 2️⃣ SOLUTION / EXPLANATION
        if (!isHint) ...[
          Card(
            color: const Color(0xFFE8F5E9), // soft green
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: MathExplanation(
                text: data!['explanation'] ?? "",
              ),
            ),
          ),
        ] else ...[
          Card(
            color: Colors.orange.shade50,
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                "User used Hint Mode. No full solution was generated.",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.deepOrange,
                ),
              ),
            ),
          ),
        ],

        const SizedBox(height: 30),

        /// 3️⃣ HINT CHAT
        if (hintChat.isNotEmpty) ...[
          const Text(
            "Hint Chat",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.orange,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          ChatHistoryView(
  messages: hintChat,
  isHintChat: true, // 🟠 orange
),
          const SizedBox(height: 30),
        ],

        /// 4️⃣ TUTOR CHAT
        if (tutorChat.isNotEmpty) ...[
          const Text(
            "Tutor Chat",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF5C87FF),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
ChatHistoryView(
  messages: tutorChat,
  isHintChat: false, // 🔵 blue
),
          const SizedBox(height: 30),
        ],

        /// 🔁 FALLBACK: OLD HISTORY
        if (hintChat.isEmpty && tutorChat.isEmpty && legacyChat.isNotEmpty) ...[
          const Text(
            "Chat History",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.black,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          ChatHistoryView(
  messages: legacyChat,
  isHintChat: isHint, // 🔵 blue
)
        ],
      ],
    ),
  ),
);
}
}
