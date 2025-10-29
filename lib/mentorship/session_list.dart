
import 'package:flutter/material.dart';
import '../services/sessionservice.dart';

class SessionListScreen extends StatefulWidget {
  const SessionListScreen({super.key});

  @override
  State<SessionListScreen> createState() => _SessionListScreenState();
}

class _SessionListScreenState extends State<SessionListScreen>
    with SingleTickerProviderStateMixin {
  final SessionService _sessionService = SessionService();
  bool isLoading = true;
  List<Map<String, dynamic>> sessions = [];

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadSessions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    setState(() => isLoading = true);
    try {
      final data = await _sessionService.getMentorSessions();
      setState(() {
        sessions = data;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      if(mounted){
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to load sessions: $e")),
      );}
    }
  }

  Future<void> _updateSessionStatus(String sessionId, String status) async {
    try {
      await _sessionService.updateSessionStatus(sessionId, status);
      _loadSessions(); // refresh
      if(mounted){
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Session $status")),
      );}
    } catch (e) {
      if(mounted){
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to update session: $e")),
      );}
    }
  }

  Future<void> _rescheduleSession(Map<String, dynamic> session) async {
    final DateTime? newDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (!mounted || newDate == null) return;

    final TimeOfDay? newTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (newTime == null) return;

    final DateTime newDateTime = DateTime(
      newDate.year,
      newDate.month,
      newDate.day,
      newTime.hour,
      newTime.minute,
    );

    try {
      await _sessionService.rescheduleSession(
        session['id'],
        newDateTime.toIso8601String().split('T')[0], // Date part
        "${newTime.hour.toString().padLeft(2, '0')}:${newTime.minute.toString().padLeft(2, '0')}", // Time part
      );
      
      _loadSessions(); // refresh
      if(mounted){
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Session rescheduled successfully!")),
      );}
    } catch (e) {
      if(mounted){
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to reschedule session: $e")),
      );}
    }
  }

  List<Map<String, dynamic>> _filterByStatus(String status) {
    return sessions.where((s) => s['status'] == status).toList();
  }

  // Enhanced responsive layout detection
  ScreenType get _screenType {
    final double width = MediaQuery.of(context).size.width;
    if (width < 600) return ScreenType.small;
    if (width < 1024) return ScreenType.medium;
    return ScreenType.large;
  }

  // Responsive padding values
  EdgeInsets get _screenPadding {
    switch (_screenType) {
      case ScreenType.small:
        return const EdgeInsets.all(16);
      case ScreenType.medium:
        return const EdgeInsets.all(20);
      case ScreenType.large:
        return const EdgeInsets.all(24);
    }
  }

  // Responsive font sizes
  double get _titleFontSize {
    switch (_screenType) {
      case ScreenType.small:
        return 16;
      case ScreenType.medium:
        return 18;
      case ScreenType.large:
        return 20;
    }
  }

  double get _bodyFontSize {
    switch (_screenType) {
      case ScreenType.small:
        return 14;
      case ScreenType.medium:
        return 16;
      case ScreenType.large:
        return 16;
    }
  }

  // Responsive icon sizes
  double get _iconSize {
    switch (_screenType) {
      case ScreenType.small:
        return 16;
      case ScreenType.medium:
        return 18;
      case ScreenType.large:
        return 20;
    }
  }

  // Responsive button padding
  EdgeInsets get _buttonPadding {
    switch (_screenType) {
      case ScreenType.small:
        return const EdgeInsets.symmetric(horizontal: 12, vertical: 10);
      case ScreenType.medium:
        return const EdgeInsets.symmetric(horizontal: 16, vertical: 12);
      case ScreenType.large:
        return const EdgeInsets.symmetric(horizontal: 20, vertical: 14);
    }
  }

  // Minimum touch target size (44px for accessibility)
  double get _minTouchSize => 44;

  Widget _buildSessionList(List<Map<String, dynamic>> list) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: _screenPadding,
          child: Text(
            "No sessions here.",
            style: TextStyle(
              fontSize: _bodyFontSize,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // Use different layouts based on screen size
    if (_screenType == ScreenType.large) {
      return _buildGridView(list);
    } else {
      return _buildListView(list);
    }
  }

  Widget _buildListView(List<Map<String, dynamic>> list) {
    return RefreshIndicator(
      onRefresh: _loadSessions,
      child: ListView.builder(
        padding: _screenPadding.copyWith(top: 12, bottom: 12),
        itemCount: list.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: EdgeInsets.only(bottom: _screenType == ScreenType.small ? 12 : 16),
            child: _buildSessionCard(list[index]),
          );
        },
      ),
    );
  }

  Widget _buildGridView(List<Map<String, dynamic>> list) {
    return RefreshIndicator(
      onRefresh: _loadSessions,
      child: GridView.builder(
        padding: _screenPadding,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _screenType == ScreenType.large ? 3 : 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: _screenType == ScreenType.large ? 1.6 : 1.4,
        ),
        itemCount: list.length,
        itemBuilder: (context, index) {
          return _buildSessionCard(list[index]);
        },
      ),
    );
  }

  Widget _buildSessionCard(Map<String, dynamic> session) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final status = session['status'] ?? 'pending';
    final isPending = status == 'pending';
    final isAccepted = status == 'accepted';

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isDark ? Colors.grey[850] : Colors.white,
      child: Padding(
        padding: _screenPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              children: [
                Icon(
                  Icons.person,
                  color: Colors.indigo,
                  size: _iconSize + 2,
                ),
                SizedBox(width: _screenType == ScreenType.small ? 12 : 16),
                Expanded(
                  child: Text(
                    "${session['profiles_new']?['username'] ?? 'Unknown User'} "
                    "(${session['session_type'] ?? 'N/A'})",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: _titleFontSize,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!isPending)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: _screenType == ScreenType.small ? 8 : 12,
                      vertical: _screenType == ScreenType.small ? 4 : 6,
                    ),
                    decoration: BoxDecoration(
                      color: status == 'accepted' 
                          ? Colors.green.withAlpha(25)
                          : status == 'rescheduled'
                          ? Colors.orange.withAlpha(25)
                          : Colors.red.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: _screenType == ScreenType.small ? 10 : 12,
                        color: status == 'accepted' 
                            ? Colors.green 
                            : status == 'rescheduled'
                            ? Colors.orange
                            : Colors.red,
                      ),
                    ),
                  ),
              ],
            ),
            
            SizedBox(height: _screenType == ScreenType.small ? 12 : 16),
            
            // Session Details
            _buildDetailRow(
              Icons.calendar_today,
              "Date: ${session['session_date'] ?? 'N/A'} at ${session['session_time'] ?? 'N/A'}",
            ),
            
            SizedBox(height: _screenType == ScreenType.small ? 8 : 12),
            
            _buildDetailRow(
              Icons.note,
              "Notes: ${session['notes'] ?? 'None'}",
            ),

            // Rescheduled info if applicable
            if (session['rescheduled_at'] != null) ...[
              SizedBox(height: _screenType == ScreenType.small ? 8 : 12),
              _buildDetailRow(
                Icons.schedule,
                "Rescheduled on: ${_formatRescheduledDate(session['rescheduled_at'])}",
              ),
            ],
            
            // Action Buttons
            SizedBox(height: _screenType == ScreenType.small ? 16 : 20),
            _buildActionButtons(session, isPending, isAccepted),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String text) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: _iconSize,
          color: isDark ? Colors.white60 : Colors.black54,
        ),
        SizedBox(width: _screenType == ScreenType.small ? 8 : 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: _bodyFontSize,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(Map<String, dynamic> session, bool isPending, bool isAccepted) {
    // For small screens, stack buttons vertically
    if (_screenType == ScreenType.small && (isPending || isAccepted)) {
      return Column(
        children: _buildButtonChildren(session, isPending, isAccepted, true),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: _buildButtonChildren(session, isPending, isAccepted, false),
    );
  }

  List<Widget> _buildButtonChildren(Map<String, dynamic> session, bool isPending, bool isAccepted, bool isVertical) {
    final children = <Widget>[];
    
    if (isPending) {
      children.addAll([
        _buildActionButton(
          icon: Icons.check,
          label: "Accept",
          color: Colors.green,
          onPressed: () => _updateSessionStatus(session['id'], 'accepted'),
          isVertical: isVertical,
        ),
        if (isVertical) SizedBox(height: 8) else SizedBox(width: 12),
        _buildActionButton(
          icon: Icons.schedule,
          label: "Reschedule",
          color: Colors.orange,
          onPressed: () => _rescheduleSession(session),
          isVertical: isVertical,
        ),
        if (isVertical) SizedBox(height: 8) else SizedBox(width: 12),
        _buildActionButton(
          icon: Icons.close,
          label: "Decline",
          color: Colors.red,
          onPressed: () => _updateSessionStatus(session['id'], 'declined'),
          isVertical: isVertical,
        ),
      ]);
    } else if (isAccepted) {
      children.addAll([
        _buildActionButton(
          icon: Icons.schedule,
          label: "Reschedule",
          color: Colors.orange,
          onPressed: () => _rescheduleSession(session),
          isVertical: isVertical,
        ),
        if (isVertical) SizedBox(height: 8) else SizedBox(width: 12),
        _buildActionButton(
          icon: Icons.cancel,
          label: "Cancel",
          color: Colors.red,
          onPressed: () => _updateSessionStatus(session['id'], 'cancelled'),
          isVertical: isVertical,
        ),
      ]);
    }
    
    return children;
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
    required bool isVertical,
  }) {
    return SizedBox(
      width: isVertical ? double.infinity : null,
      height: _minTouchSize,
      child: ElevatedButton.icon(
        icon: Icon(icon, size: _iconSize),
        label: Text(
          label,
          style: TextStyle(fontSize: _bodyFontSize),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: _buttonPadding,
          minimumSize: Size(_minTouchSize, _minTouchSize),
        ),
        onPressed: onPressed,
      ),
    );
  }

  String _formatRescheduledDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Session Requests"),
        backgroundColor: primaryColor,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          labelStyle: TextStyle(
            fontSize: _bodyFontSize,
            fontWeight: FontWeight.w500,
          ),
          tabs: const [
            Tab(text: "Pending"),
            Tab(text: "Accepted"),
            Tab(text: "Declined"),
          ],
        ),
      ),
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildSessionList(_filterByStatus('pending')),
                  _buildSessionList(_filterByStatus('accepted')),
                  _buildSessionList(_filterByStatus('declined')),
                ],
              ),
      ),
    );
  }
}

enum ScreenType { small, medium, large }