import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'HistoryDetailScreen.dart';
import 'main.dart'; // for Config.baseUrl

class TopicHistoryScreen extends StatefulWidget {
  final String topic;
  final String userId;

  const TopicHistoryScreen({
    super.key,
    required this.topic,
    required this.userId,
  });

  @override
  State<TopicHistoryScreen> createState() => _TopicHistoryScreenState();
}

class _TopicHistoryScreenState extends State<TopicHistoryScreen> {
  List<dynamic> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchTopicHistory();
  }

  Future<void> _fetchTopicHistory() async {
    try {
      final response = await http.get(
        Uri.parse(
          "${Config.baseUrl}/api/history?user_id=${widget.userId}",
        ),
      );

      if (response.statusCode == 200) {
        final List all = jsonDecode(response.body);

        setState(() {
          _items = all
              .where((e) => e['topic'] == widget.topic)
              .toList();
          _loading = false;
        });
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.topic),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text("No problems found"))
              : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 8,
                      ),
                      child: ListTile(
                        title: Text(
                          item['equation'] ?? "Unknown Problem",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(item['timestamp'] ?? ""),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => HistoryDetailScreen(
                                historyId: item['_id'].toString(),
                                userId: widget.userId,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
