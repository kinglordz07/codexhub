import 'package:flutter/material.dart';
import 'package:codexhub01/mentorship/resourcelibrary_screen.dart';
import 'package:codexhub01/parts/profilescreen.dart';
import 'package:codexhub01/mentorship/friendlst.dart';
import 'package:codexhub01/mentorship/session_list.dart';
import 'package:codexhub01/mentorship/mentor_invites.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';

final supabase = Supabase.instance.client;

class MentorDashboardScreen extends StatelessWidget {
  MentorDashboardScreen({super.key});

  final List<Map<String, dynamic>> mentorFeatures = [
    {
      'title': 'Resource Library',
      'icon': Icons.library_books,
      'route': ResourceLibraryScreen(),
    },
    {
      'title': 'Friend List',
      'icon': Icons.smart_toy_outlined,
      'route': MentorFriendPage(),
    },
    {
      'title': 'Scheduled Session',
      'icon': Icons.calendar_today,
      'route': SessionListScreen(),
    },
    {
      'title': 'Live Invites',
      'icon': Icons.video_call,
      'route': MentorInvites(mentorId: supabase.auth.currentUser?.id ?? ''),
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

    // Adaptive grid layout
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Mentor Dashboard',
          style: TextStyle(fontSize: isSmallScreen ? 18 : 20,
          color: Colors.white,
          fontWeight: FontWeight.bold,
          ),
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
              padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
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
                      fontSize: isSmallScreen ? 20 : 24,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : primary,
                    ),
                  ),
                  SizedBox(height: isSmallScreen ? 6 : 8),
                  Text(
                    'Manage your mentorship activities and help others grow',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 14 : 16,
                      color: isDark ? Colors.white70 : primary.withAlpha(200),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Features Grid
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                child: GridView.builder(
                  itemCount: mentorFeatures.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: isSmallScreen ? 12 : 16,
                    mainAxisSpacing: isSmallScreen ? 12 : 16,
                    childAspectRatio: _getAspectRatio(screenSize, isLandscape),
                  ),
                  itemBuilder: (context, index) {
                    final feature = mentorFeatures[index];
                    return _DashboardTile(
                      title: feature['title'],
                      iconData: feature['icon'],
                      primaryColor: primary,
                      isDark: isDark,
                      screenSize: screenSize,
                      isSmallScreen: isSmallScreen,
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
  }

  double _getAspectRatio(Size screenSize, bool isLandscape) {
    if (screenSize.width > 1200) return 1.2;
    if (screenSize.width > 800) return 1.1;
    if (isLandscape) return 0.9;
    return 1.0;
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

  const _DashboardTile({
    required this.title,
    required this.iconData,
    required this.onTap,
    required this.primaryColor,
    required this.isDark,
    required this.screenSize,
    required this.isSmallScreen,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      splashColor: primaryColor.withAlpha(51), // 0.2 opacity
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 6,
        color: isDark ? Colors.grey[850] : Colors.white,
        shadowColor: isDark ? Colors.black45 : Colors.black12,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isSmallScreen ? 8 : 12,
            vertical: isSmallScreen ? 16 : 20,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                iconData,
                size: _getIconSize(),
                color: primaryColor,
              ),
              SizedBox(height: isSmallScreen ? 8 : 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: _getFontSize(),
                  color: isDark ? Colors.white : Colors.black87,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _getIconSize() {
    if (screenSize.width > 1200) return 60;
    if (screenSize.width > 800) return 55;
    if (screenSize.width > 600) return 50;
    return 45;
  }

  double _getFontSize() {
    if (screenSize.width > 1200) return 18;
    if (screenSize.width > 800) return 17;
    if (screenSize.width > 600) return 16;
    return 14;
  }
}