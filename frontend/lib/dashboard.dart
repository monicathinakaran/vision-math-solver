import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'main.dart'; // for Config.baseUrl
import 'package:fl_chart/fl_chart.dart';

Future<List<dynamic>> fetchDashboardTopics() async {
  final res = await http.get(
    Uri.parse("${Config.baseUrl}/api/dashboard/topics"),
  );

  if (res.statusCode == 200) {
    return jsonDecode(res.body);
  }
  return [];
}

Widget topicList(List topics) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        "Topics Practiced",
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 10),
      ...topics.map(
        (t) => ListTile(
          leading: const Icon(Icons.book_outlined),
          title: Text(t['topic']),
          trailing: Text(
            t['count'].toString(),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
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

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Dashboard"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: FutureBuilder(
          future: fetchDashboardTopics(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final topics = snapshot.data as List;

            if (topics.isEmpty) {
              return const Center(child: Text("No activity yet."));
            }

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  topicPieChart(topics),
                  const SizedBox(height: 25),
                  topicList(topics),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}