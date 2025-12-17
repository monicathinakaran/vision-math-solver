import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart'; // for Config.baseUrl
import 'package:fl_chart/fl_chart.dart';
import 'topic_history_screen.dart';

Future<List<dynamic>> fetchDashboardTopics() async {
  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getString("user_id");

  if (userId == null) return [];

  final res = await http.get(
    Uri.parse(
      "${Config.baseUrl}/api/dashboard/topics?user_id=$userId"
    ),
  );

  if (res.statusCode == 200) {
    return jsonDecode(res.body);
  }
  return [];
}

Widget topicList(BuildContext context, List topics) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        "Topics Practiced",
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 10),
      ...topics.map(
  (t) {
    final topicName = t['topic'];
    final count = t['count'];

    return ListTile(
      leading: const Icon(Icons.bookmark_border),
      title: Text(topicName),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            count.toString(),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
IconButton(
  icon: const Icon(Icons.arrow_forward_ios, size: 16),
  onPressed: () async {
    final userId = await getUserId();
    if (userId == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TopicHistoryScreen(
          topic: topicName,
          userId: userId, // ✅ THIS WAS MISSING
        ),
      ),
    );
  },
),


        ],
      ),
    );
  },
),
    ],
  );
}

Widget topicPieChart(List topics) {
  final colors = [
    Colors.blue,
    Colors.orange,
    Colors.green,
    Colors.purple,
    Colors.red,
    Colors.teal,
  ];

  return SizedBox(
    height: 250,
    child: PieChart(
      PieChartData(
        sections: List.generate(topics.length, (i) {
          return PieChartSectionData(
            value: topics[i]['count'].toDouble(),
            title: topics[i]['topic'],
            color: colors[i % colors.length],
            radius: 80,
            titleStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          );
        }),
        sectionsSpace: 2,
        centerSpaceRadius: 40,
      ),
    ),
  );
}

class Dashboard extends StatelessWidget {
  const Dashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Dashboard"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: FutureBuilder<List<dynamic>>(
        future: fetchDashboardTopics(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("No data yet"));
          }

          final topics = snapshot.data!;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                topicPieChart(topics),
                const SizedBox(height: 30),
                topicList(context, topics),
              ],
            ),
          );
        },
      ),
    );
  }
}