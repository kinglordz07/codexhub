// ignore_for_file: file_names

import 'package:flutter/material.dart';
import 'package:codexhub01/mentorship/schedulesession_screen.dart';
import 'package:codexhub01/parts/mysessionlist.dart';

class SessionsTabScreen extends StatefulWidget {
  const SessionsTabScreen({super.key});

  @override
  State<SessionsTabScreen> createState() => _SessionsTabScreenState();
}

class _SessionsTabScreenState extends State<SessionsTabScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Sessions"),
        backgroundColor: Colors.indigo,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "Schedule Session"),
            Tab(text: "My Sessions"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          ScheduleSessionScreen(), // Form to schedule new session
          MySessionsScreen(),      // List of user's sessions
        ],
      ),
    );
  }
}
