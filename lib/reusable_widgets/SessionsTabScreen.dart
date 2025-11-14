// ignore_for_file: file_names

import 'package:flutter/material.dart';
import 'package:codexhub01/parts/schedulesession_screen.dart';
import 'package:codexhub01/parts/mysessionlist.dart';

class SessionsTabScreen extends StatefulWidget {
  const SessionsTabScreen({super.key});

  @override
  State<SessionsTabScreen> createState() => _SessionsTabScreenState();
}

class _SessionsTabScreenState extends State<SessionsTabScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  int _currentTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChange);
  }

  void _handleTabChange() {
    setState(() {
      _currentTabIndex = _tabController.index;
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
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
          labelColor: Colors.white,
          unselectedLabelColor: Colors.lightBlueAccent,
          tabs: const [
            Tab(text: "Schedule Session"),
            Tab(text: "My Sessions"),
          ],
        ),
      ),
      body: IndexedStack(
        index: _currentTabIndex,
        children: const [
          ScheduleSessionScreen(), // Only loads when active
          MySessionsScreen(),      // Only loads when active
        ],
      ),
    );
  }
}