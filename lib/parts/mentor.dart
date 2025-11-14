import 'package:flutter/material.dart';
import 'package:codexhub01/mentorship/resourcelibrary_screen.dart';
import 'package:codexhub01/parts/profilescreen.dart';
import 'package:codexhub01/mentorship/friendlst.dart';
import 'package:codexhub01/mentorship/session_list.dart';
import 'package:codexhub01/mentorship/mentor_invites.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import 'package:provider/provider.dart';
import '../services/notif.dart';

final supabase = Supabase.instance.client;

class MentorDashboardScreen extends StatefulWidget {
  const MentorDashboardScreen({super.key});

  @override
  State<MentorDashboardScreen> createState() => _MentorDashboardScreenState();
}

class _MentorDashboardScreenState extends State<MentorDashboardScreen> {
  final List<Map<String, dynamic>> mentorFeatures = [
    {
      'title': 'Resource Library',
      'icon': Icons.library_books,
      'route': ResourceLibraryScreen(),
      'hasNotifications': false,
    },
    {
      'title': 'Friend List',
      'icon': Icons.smart_toy_outlined,
      'route': MentorFriendPage(),
      'hasNotifications': true, // 🔴 CAN SHOW NOTIFICATIONS
    },
    {
      'title': 'Scheduled Session',
      'icon': Icons.calendar_today,
      'route': SessionListScreen(),
      'hasNotifications': true, // 🔴 CAN SHOW NOTIFICATIONS
    },
    {
      'title': 'Live Invites',
      'icon': Icons.video_call,
      'route': MentorInvites(mentorId: supabase.auth.currentUser?.id ?? ''),
      'hasNotifications': true, // 🔴 CAN SHOW NOTIFICATIONS
    },
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;
    final isLandscape = screenSize.width > screenSize.height;

    int crossAxisCount;
    if (screenSize.width > 1200) {
      crossAxisCount = 4; 
    } else if (screenSize.width > 800) {
      crossAxisCount = 3; 
    } else if (screenSize.width > 600 || isLandscape) {
      crossAxisCount = 2; 
    } else {
      crossAxisCount = 2;
    }

    return Consumer<NotificationState>(
      builder: (context, notificationState, child) {
        // 🔴 CHECK NOTIFICATION SETTING
        final bool showNotifications = NotificationService.areNotificationsAllowed;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              'Mentor Dashboard',
              style: TextStyle(
                fontSize: isSmallScreen ? 18 : 20,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            flexibleSpace: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.indigo.shade700, Colors.indigo.shade900],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            centerTitle: true,
            elevation: 4,
            automaticallyImplyLeading: false,
            actions: [
              // 🔴 NOTIFICATION INDICATOR IN APP BAR
              if (showNotifications && notificationState.hasNotifications)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Stack(
                    children: [
                      Icon(Icons.notifications, color: Colors.white, size: isSmallScreen ? 20 : 24),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              IconButton(
                icon: Icon(
                  Icons.person,
                  size: isSmallScreen ? 20 : 24,
                ),
                tooltip: "Profile Settings",
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfileScreen(themeNotifier: themeNotifier),
                  ),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                // Welcome Header
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [Colors.grey[850]!, Colors.grey[800]!]
                          : [primary.withAlpha(30), primary.withAlpha(15)],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome, Mentor!',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 18 : 24,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : primary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: isSmallScreen ? 4 : 8),
                      Text(
                        'Manage your mentorship activities and help others grow',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 12 : 16,
                          color: isDark ? Colors.white70 : primary.withAlpha(200),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // 🔴 NOTIFICATION SUMMARY BANNER
                if (showNotifications && notificationState.hasNotifications && _isUserLoggedIn())
                  GestureDetector(
                    onTap: _showNotificationSummary,
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
                      margin: EdgeInsets.all(isSmallScreen ? 8 : 12),
                      decoration: BoxDecoration(
                        color: Colors.red.withAlpha(30),
                        border: Border.all(color: Colors.red),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.notifications_active, color: Colors.red, size: isSmallScreen ? 16 : 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'You have new notifications',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: isSmallScreen ? 12 : 14,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Row(
                                  children: [
                                    if (notificationState.pendingFriendRequests > 0)
                                      _buildNotificationSummaryChip(
                                        '${notificationState.pendingFriendRequests} Friend Requests',
                                        Colors.blue,
                                        isSmallScreen,
                                      ),
                                    if (notificationState.unreadMessages > 0)
                                      _buildNotificationSummaryChip(
                                        '${notificationState.unreadMessages} Unread Messages',
                                        Colors.green,
                                        isSmallScreen,
                                      ),
                                    if (notificationState.pendingSessions > 0)
                                      _buildNotificationSummaryChip(
                                        '${notificationState.pendingSessions} Pending Sessions',
                                        Colors.orange,
                                        isSmallScreen,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios, color: Colors.red, size: isSmallScreen ? 12 : 16),
                        ],
                      ),
                    ),
                  ),

                // Features Grid
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
                    child: GridView.builder(
                      itemCount: mentorFeatures.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: isSmallScreen ? 12 : 16,
                        mainAxisSpacing: isSmallScreen ? 12 : 16,
                        childAspectRatio: _getAspectRatio(screenSize, crossAxisCount),
                      ),
                      itemBuilder: (context, index) {
                        final feature = mentorFeatures[index];
                        final hasNotificationFeature = feature['hasNotifications'] as bool;
                        
                        // 🔴 FIXED NOTIFICATION LOGIC
                        final bool shouldShowNotification = showNotifications && 
                            hasNotificationFeature && 
                            _hasNotificationsForFeature(feature['title'], notificationState);
                        
                        return _DashboardTile(
                          title: feature['title'],
                          iconData: feature['icon'],
                          primaryColor: primary,
                          isDark: isDark,
                          screenSize: screenSize,
                          isSmallScreen: isSmallScreen,
                          hasNotification: shouldShowNotification,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => feature['route']),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isUserLoggedIn() {
    return !isOfflineMode && (supabase.auth.currentUser != null);
  }

  bool _hasNotificationsForFeature(String featureTitle, NotificationState notificationState) {
    switch (featureTitle) {
      case 'Friend List':
        return notificationState.pendingFriendRequests > 0 || notificationState.unreadMessages > 0;
      case 'Scheduled Session':
        return notificationState.pendingSessions > 0;
      case 'Live Invites':
        // You might want to add a separate count for live invites
        return notificationState.pendingSessions > 0; // Using sessions as placeholder
      default:
        return false;
    }
  }

  Widget _buildNotificationSummaryChip(String text, Color color, bool isSmallScreen) {
    return Container(
      margin: EdgeInsets.only(right: 8),
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: isSmallScreen ? 9 : 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  void _showNotificationSummary() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.notifications, color: Colors.red),
            SizedBox(width: 8),
            Text('Notifications Summary'),
          ],
        ),
        content: Consumer<NotificationState>(
          builder: (context, notificationState, child) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (notificationState.pendingFriendRequests > 0)
                  _buildNotificationDetailItem(
                    Icons.person_add,
                    'Friend Requests',
                    '${notificationState.pendingFriendRequests} pending',
                    Colors.blue,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => MentorFriendPage()),
                      );
                    },
                  ),
                if (notificationState.unreadMessages > 0)
                  _buildNotificationDetailItem(
                    Icons.message,
                    'Unread Messages',
                    '${notificationState.unreadMessages} unread',
                    Colors.green,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => MentorFriendPage()),
                      );
                    },
                  ),
                if (notificationState.pendingSessions > 0)
                  _buildNotificationDetailItem(
                    Icons.calendar_today,
                    'Pending Sessions',
                    '${notificationState.pendingSessions} awaiting response',
                    Colors.orange,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => SessionListScreen()),
                      );
                    },
                  ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationDetailItem(IconData icon, String title, String subtitle, Color color, {VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
    );
  }

  double _getAspectRatio(Size screenSize, int crossAxisCount) {
    switch (crossAxisCount) {
      case 4:
        return 1.0;
      case 3:
        return 1.0;
      case 2:
        return screenSize.width > 600 ? 1.2 : 1.1;
      default:
        return 1.0;
    }
  }
}

class _DashboardTile extends StatelessWidget {
  final String title;
  final IconData iconData;
  final VoidCallback onTap;
  final Color primaryColor;
  final bool isDark;
  final Size screenSize;
  final bool isSmallScreen;
  final bool hasNotification;

  const _DashboardTile({
    required this.title,
    required this.iconData,
    required this.onTap,
    required this.primaryColor,
    required this.isDark,
    required this.screenSize,
    required this.isSmallScreen,
    this.hasNotification = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: hasNotification ? 4 : 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: hasNotification ? Colors.blue.shade50 : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: BoxConstraints(
            minHeight: 120,
          ),
          child: Stack(
            children: [
              // Main centered content
              Center(
                child: Padding(
                  padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        iconData,
                        size: _getIconSize(),
                        color: hasNotification ? Colors.indigo : primaryColor,
                      ),
                      SizedBox(height: isSmallScreen ? 8 : 12),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: _getFontSize(),
                          color: hasNotification ? Colors.indigo : (isDark ? Colors.white : Colors.black87),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              // Notification indicator
              if (hasNotification)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: isSmallScreen ? 12 : 16,
                    height: isSmallScreen ? 12 : 16,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? Colors.grey[850]! : Colors.white,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withAlpha(128),
                          blurRadius: 4,
                          spreadRadius: 1,
                        )
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  double _getIconSize() {
    if (screenSize.width > 1200) return 48;
    if (screenSize.width > 800) return 44;
    if (screenSize.width > 600) return 40;
    return 36;
  }

  double _getFontSize() {
    if (screenSize.width > 1200) return 16;
    if (screenSize.width > 800) return 15;
    if (screenSize.width > 600) return 14;
    return 12;
  }
}