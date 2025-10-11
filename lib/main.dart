import 'package:flutter/material.dart';
import 'package:codexhub01/parts/code_editor.dart';
import 'package:codexhub01/parts/learning_tools.dart';
import 'package:codexhub01/parts/mentorship.dart';
import 'package:codexhub01/parts/profilescreen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:codexhub01/collabscreen/lobby.dart';
import 'package:codexhub01/parts/log_in.dart';
import 'package:codexhub01/utils/resetpasscallback.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:codexhub01/utils/forgotpass.dart';
import 'package:codexhub01/mentorship/friendlst.dart';
import 'package:codexhub01/parts/create_live_lobby.dart';
import 'package:codexhub01/mentorship/schedulesession_screen.dart';
import 'package:codexhub01/parts/intro_screen.dart'; // ✅ make sure this path matches your file

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
late final SupabaseClient supabase;
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('Caught error: ${details.exception}');
  };

  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('isDarkMode') ?? false;
  themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;

  try {
    const url = 'https://ohvelhlrehojqrvaqsim.supabase.co';
    const anonKey =
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9odmVsaGxyZWhvanFydmFxc2ltIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQ0ODExMTIsImV4cCI6MjA3MDA1NzExMn0.qo4Cd5B8IzcYZ-I5aVDsqYo3l1DAwwWF_fauNAVu1BE';

    await Supabase.initialize(url: url, anonKey: anonKey);
    supabase = Supabase.instance.client;
    debugPrint('Supabase initialized successfully');
  } catch (e, stackTrace) {
    debugPrint('Failed to initialize Supabase: $e');
    debugPrint('Stack trace: $stackTrace');
  }

  runApp(const CodeHubApp());
}

class CodeHubApp extends StatelessWidget {
  const CodeHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, themeMode, child) {
        return MaterialApp(
          title: 'CodeXHub',
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          theme: ThemeData(
            primarySwatch: Colors.indigo,
            scaffoldBackgroundColor: Colors.grey[100],
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              elevation: 4,
              centerTitle: true,
            ),
          ),
          darkTheme: ThemeData.dark().copyWith(
            primaryColor: Colors.indigo,
            scaffoldBackgroundColor: Colors.grey[900],
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
          ),
          themeMode: themeMode,

          // ✅ Start with IntroScreen first
          initialRoute: '/intro',

          routes: {
            '/intro': (context) => const IntroScreen(),
            '/': (context) => const SignIn(),
            '/dashboard': (context) => DashboardScreen(),
            '/forgot-password': (context) => const ForgotPasswordScreen(),
          },

          // for password reset callback
          onGenerateRoute: (settings) {
            if (settings.name == '/reset-callback') {
              final Uri? uri = settings.arguments as Uri?;
              return MaterialPageRoute(
                builder: (context) => const ResetPasswordCallback(),
                settings: RouteSettings(
                  name: '/reset-callback',
                  arguments: uri,
                ),
              );
            }
            return null;
          },
        );
      },
    );
  }
}

class DashboardScreen extends StatelessWidget {
  DashboardScreen({super.key});

  final List<Map<String, dynamic>> menuItems = [
    {
      'title': 'Collaboration Lobby',
      'icon': Icons.group_work,
      'route': CollabLobbyScreen(),
    },
    {
      'title': 'Create Live Lobby',
      'icon': Icons.video_call,
      'route': CreateLiveLobby(
        menteeId: supabase.auth.currentUser?.id ?? '',
        menteeName:
            supabase.auth.currentUser?.userMetadata?['username'] ?? 'Mentee',
      ),
    },
    {
      'title': 'Mentorship',
      'icon': Icons.support_agent,
      'route': MentorshipScreen(),
    },
    {
      'title': 'Friend List',
      'icon': Icons.smart_toy_outlined,
      'route': MentorFriendPage(),
    },
    {
      'title': 'Code Editor',
      'icon': Icons.code,
      'route': CollabCodeEditorScreen(roomId: 'test_room_123'),
    },
    {
      'title': 'User Profile',
      'icon': Icons.account_circle,
      'route': ProfileScreen(themeNotifier: themeNotifier),
    },
    {
      'title': 'Learning Tools',
      'icon': Icons.book_outlined,
      'route': LearningTools(),
    },
    {
      'title': 'Schedule Sessions',
      'icon': Icons.calendar_today,
      'route': ScheduleSessionScreen(),
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CodeXHub Dashboard'),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.builder(
          itemCount: menuItems.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1,
          ),
          itemBuilder:
              (context, index) => DashboardTile(
                title: menuItems[index]['title'] as String,
                iconData: menuItems[index]['icon'] as IconData,
                screen: menuItems[index]['route'] as Widget,
              ),
        ),
      ),
    );
  }
}

class DashboardTile extends StatelessWidget {
  final String title;
  final IconData iconData;
  final Widget screen;

  const DashboardTile({
    super.key,
    required this.title,
    required this.iconData,
    required this.screen,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => screen),
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(iconData, size: 40, color: Colors.indigo),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
