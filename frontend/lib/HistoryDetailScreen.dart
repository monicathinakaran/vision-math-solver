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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isHint = data!['mode_used'] == "hint";

    return Scaffold(
      appBar: AppBar(title: const Text("History Detail")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            /// 1️⃣ FINAL OCR / EDITED PROBLEM
            Card(
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
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: MathExplanation(text: data!['explanation']),
                ),
              ),
            ] else ...[
              Card(
                color: Colors.orange.shade50,
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    "User used Hint Mode. No full solution was generated.",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 30),

            /// 3️⃣ HINT CHAT
            if ((data!['hint_chat'] ?? []).isNotEmpty) ...[
              const Text("Hint Chat", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              ChatHistoryView(messages: data!['hint_chat']),
              const SizedBox(height: 30),
            ],

            /// 4️⃣ TUTOR CHAT
            if ((data!['tutor_chat'] ?? []).isNotEmpty) ...[
              const Text("Tutor Chat", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              ChatHistoryView(messages: data!['tutor_chat']),
            ],
          ],
        ),
      ),
    );
  }
}
