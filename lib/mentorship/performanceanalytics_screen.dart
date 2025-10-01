import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart'; // External package for graphs

class PerformanceAnalyticsScreen extends StatelessWidget {
   PerformanceAnalyticsScreen({super.key});

  final List<Map<String, dynamic>> menteeProgress = [
    {'name': 'Juan Dela Cruz', 'progress': 80},
    {'name': 'Maria Santos', 'progress': 60},
    {'name': 'Luis Gomez', 'progress': 90},
    {'name': 'Ana Lopez', 'progress': 45},
  ];

  List<FlSpot> generateProgressSpots() {
    return List.generate(menteeProgress.length, (index) {
      return FlSpot(index.toDouble(), menteeProgress[index]['progress'].toDouble());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Performance Analytics'), backgroundColor: Colors.indigo),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text("Mentee Progress Overview", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 16),

            Expanded(
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: true),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true)),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true)),
                  ),
                  borderData: FlBorderData(show: true),
                  lineBarsData: [
                    LineChartBarData(
                      spots: generateProgressSpots(),
                      isCurved: true,
                      color: Colors.indigo,
                      barWidth: 4,
                      // ignore: deprecated_member_use
                      belowBarData: BarAreaData(show: true, color: Colors.indigo.withOpacity(0.3)),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 20),

            // Additional Summary
            Expanded(
              child: ListView.builder(
                itemCount: menteeProgress.length,
                itemBuilder: (context, index) {
                  return Card(
                    margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    elevation: 5,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      title: Text(menteeProgress[index]['name'], style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("Overall Progress: ${menteeProgress[index]['progress']}%"),
                      leading: Icon(Icons.bar_chart, size: 40, color: Colors.indigo),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}