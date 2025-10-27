import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; 

// 🔹 Screens
import 'package:codexhub01/parts/log_in.dart';
import 'package:codexhub01/parts/intro_screen.dart';
import 'package:codexhub01/parts/learning_tools.dart';
import 'package:codexhub01/parts/code_editor.dart';
import 'package:codexhub01/parts/profilescreen.dart';
import 'package:codexhub01/utils/forgotpass.dart';
import 'package:codexhub01/utils/newpass.dart';
import 'package:codexhub01/collabscreen/lobby.dart';
import 'package:codexhub01/mentorship/friendlst.dart';
import 'package:codexhub01/reusable_widgets/SessionsTabScreen.dart';

// 🔹 App Links
import 'package:codexhub01/utils/uni_link_listener.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
late final SupabaseClient supabase;
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);
bool isOfflineMode = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 🔹 Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // 🔹 Load saved theme
  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('isDarkMode') ?? false;
  themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;

  // 🔹 Check connectivity and initialize Supabase
  await initializeApp();

  runApp(const CodeHubApp());
}

Future<void> initializeApp() async {
  try {
    // Check internet connectivity
    final connectivityResult = await Connectivity().checkConnectivity();
    final hasInternet = connectivityResult.any((result) => result != ConnectivityResult.none);
    
    debugPrint('🌐 Internet connectivity: $hasInternet');
    
    if (!hasInternet) {
      isOfflineMode = true;
      debugPrint('🔴 No internet connection - Starting in offline mode');
      return;
    }

    // Try to initialize Supabase with timeout
    const url = 'https://ohvelhlrehojqrvaqsim.supabase.co';
    const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9odmVsaGxyZWhvanFydmFxc2ltIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQ0ODExMTIsImV4cCI6MjA3MDA1NzExMn0.qo4Cd5B8IzcYZ-I5aVDsqYo3l1DAwwWF_fauNAVu1BE';
    
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
    );
    
    // Test the connection
    supabase = Supabase.instance.client;
    await supabase.from('profiles_new').select('count').limit(1).timeout(const Duration(seconds: 10));
    
    isOfflineMode = false;
    debugPrint('✅ Supabase initialized successfully - Online mode');
    
  } catch (e, st) {
    debugPrint('❌ Supabase init failed: $e');
    debugPrint('Stack trace: $st');
    isOfflineMode = true;
    debugPrint('🔴 Falling back to offline mode');
    
    // Save offline mode preference
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isOfflineMode', true);
  }
}

class CodeHubApp extends StatefulWidget {
  const CodeHubApp({super.key});

  @override
  State<CodeHubApp> createState() => _CodeHubAppState();
}

class _CodeHubAppState extends State<CodeHubApp> {
  final AppLinkListener _appLinkListener = AppLinkListener();
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Load offline mode preference
    final prefs = await SharedPreferences.getInstance();
    final savedOfflineMode = prefs.getBool('isOfflineMode') ?? false;
    
    if (savedOfflineMode) {
      isOfflineMode = true;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = navigatorKey.currentContext;
      if (context != null && mounted) {
        _appLinkListener.init(navigatorKey);
        
        // Auto-redirect based on offline mode
        if (isOfflineMode) {
          Navigator.of(navigatorKey.currentContext!).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const DashboardScreen()),
            (route) => false,
          );
        }
      }
    });

    setState(() {
      _isInitialized = true;
    });
  }

  @override
  void dispose() {
    _appLinkListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Initializing...'),
                if (isOfflineMode) ...[
                  SizedBox(height: 8),
                  Text('Offline Mode', style: TextStyle(color: Colors.orange)),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, themeMode, child) {
        return MaterialApp(
          title: 'CodeXHub',
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          themeMode: themeMode,
          theme: ThemeData.light(useMaterial3: true).copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.indigo,
              brightness: Brightness.light,
            ),
            scaffoldBackgroundColor: Colors.grey[100],
          ),
          darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
            primaryColor: Colors.indigo,
            scaffoldBackgroundColor: Colors.grey[900],
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.indigo,
              brightness: Brightness.dark,
            ),
          ),
          initialRoute: isOfflineMode ? '/dashboard' : '/intro',
          routes: {
            '/intro': (context) => const IntroScreen(),
            '/': (context) => const SignIn(),
            '/dashboard': (context) => const DashboardScreen(),
            '/forgot-password': (context) => const ForgotPasswordScreen(),
            '/code-editor-offline': (context) => CollabCodeEditorScreen(
                  roomId: 'offline_editor_${DateTime.now().millisecondsSinceEpoch}',
                  isMentor: true,
                ),
          },
          onGenerateRoute: (settings) {
            if (settings.name == '/reset-callback') {
              final Uri? uri = settings.arguments as Uri?;
              final token = uri?.queryParameters['token'];
              return MaterialPageRoute(
                builder: (context) => UpdatePasswordScreen(token: token),
                settings: RouteSettings(name: '/reset-callback', arguments: uri),
              );
            }
            return null;
          },
        );
      },
    );
  }
}

// Add this method to manually toggle offline mode
Future<void> toggleOfflineMode(bool offline) async {
  isOfflineMode = offline;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('isOfflineMode', offline);
  
  // Force app rebuild
  if (navigatorKey.currentContext != null) {
    Navigator.of(navigatorKey.currentContext!).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const DashboardScreen()),
      (route) => false,
    );
  }
}

// ---------- Responsive Dashboard ----------

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  StreamSubscription? _callSub;
  bool _isUserLoggedIn = false;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    
    // In offline mode, no user is logged in
    _isUserLoggedIn = !isOfflineMode && (supabase.auth.currentUser != null);

    if (_isUserLoggedIn && !isOfflineMode) {
      _listenToIncomingCalls();
    }

    // Listen for connectivity changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((result) {
      final hasInternet = result.any((connectivity) => connectivity != ConnectivityResult.none);
      if (hasInternet && isOfflineMode) {
        // Internet restored - offer to go back online
        _showReconnectionDialog();
      } else if (!hasInternet && !isOfflineMode) {
        // Internet lost - switch to offline mode
        toggleOfflineMode(true);
      }
    });
  }

  void _showReconnectionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Internet Restored'),
        content: Text('Do you want to switch back to online mode?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Stay Offline'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              toggleOfflineMode(false);
            },
            child: Text('Go Online'),
          ),
        ],
      ),
    );
  }

  void _listenToIncomingCalls() {
    if (isOfflineMode) return;
    
    try {
      _callSub = supabase.from('calls').stream(primaryKey: ['id']).listen((calls) {
        debugPrint("📞 Incoming call data: $calls");
      });
    } catch (e) {
      debugPrint('Error listening to calls: $e');
    }
  }

  @override
  void dispose() {
    _callSub?.cancel();
    _connectivitySubscription.cancel();
    super.dispose();
  }

  List<Map<String, dynamic>> get menuItems {
    // In offline mode, ONLY show offline-available features
    if (isOfflineMode) {
      return [
        {
          'title': 'Code Editor',
          'icon': Icons.code,
          'route': CollabCodeEditorScreen(
            roomId: 'offline_editor_${DateTime.now().millisecondsSinceEpoch}',
            isMentor: true,
          ),
          'availableOffline': true,
        },
        {
          'title': 'Learning Tools',
          'icon': Icons.book_outlined,
          'route': LearningTools(),
          'availableOffline': true,
        },
        {
          'title': 'Go Online',
          'icon': Icons.wifi,
          'route': _ReconnectScreen(),
          'availableOffline': true,
        },
      ];
    }

    // Online mode - show features based on login status
    final baseItems = [
      {
        'title': 'Code Editor',
        'icon': Icons.code,
        'route': CollabCodeEditorScreen(
          roomId: 'editor_${DateTime.now().millisecondsSinceEpoch}',
          isMentor: true,
        ),
        'availableOffline': true,
      },
      {
        'title': 'Learning Tools',
        'icon': Icons.book_outlined,
        'route': LearningTools(),
        'availableOffline': true,
      },
    ];

    if (_isUserLoggedIn) {
      baseItems.addAll([
        {
          'title': 'Collaboration Lobby',
          'icon': Icons.group_work,
          'route': CollabLobbyScreen(),
          'availableOffline': false,
        },
        {
          'title': 'Friend List',
          'icon': Icons.people,
          'route': MentorFriendPage(),
          'availableOffline': false,
        },
        {
          'title': 'User Profile',
          'icon': Icons.account_circle,
          'route': ProfileScreen(themeNotifier: themeNotifier),
          'availableOffline': false,
        },
        {
          'title': 'Sessions Tabs',
          'icon': Icons.calendar_today,
          'route': SessionsTabScreen(),
          'availableOffline': false,
        },
      ]);
    } else {
      baseItems.add({
        'title': 'Sign In',
        'icon': Icons.login,
        'route': const SignIn(),
        'availableOffline': false,
      });
    }

    return baseItems;
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('CodeXHub Dashboard'),
        centerTitle: true,
        automaticallyImplyLeading: false,
        backgroundColor: Colors.indigo,
        actions: [
          if (isOfflineMode)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Icon(Icons.wifi_off, color: Colors.orange, size: _getIconSize(screenSize)),
                  SizedBox(width: _getSpacing(screenSize)),
                  Text('Offline', style: TextStyle(
                    color: Colors.orange, 
                    fontSize: _getFontSize(screenSize, isTitle: false)
                  )),
                  SizedBox(width: _getSpacing(screenSize)),
                  IconButton(
                    icon: Icon(Icons.wifi, color: Colors.white),
                    onPressed: () => _showReconnectionDialog(),
                    tooltip: 'Try to reconnect',
                  ),
                ],
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(_getPadding(screenSize)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isOfflineMode || !_isUserLoggedIn)
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(_getSpacing(screenSize)),
                  margin: EdgeInsets.only(bottom: _getSpacing(screenSize)),
                  decoration: BoxDecoration(
                    color: Colors.orange.withAlpha((255 * 0.1).round()),
                    border: Border.all(color: Colors.orange),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info, color: Colors.orange, size: _getIconSize(screenSize)),
                      SizedBox(width: _getSpacing(screenSize)),
                      Expanded(
                        child: Text(
                          isOfflineMode
                              ? 'Running in offline mode. Only Code Editor and Learning Tools are available.'
                              : 'Sign in to access all features.',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: _getFontSize(screenSize, isTitle: false)
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: _buildGrid(screenSize, isPortrait),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ... (rest of your existing methods remain the same)
  Widget _buildGrid(Size screenSize, bool isPortrait) {
    int crossAxisCount;
    
    if (isOfflineMode) {
      crossAxisCount = 2;
    } else if (screenSize.width > 1200) {
      crossAxisCount = 4;
    } else if (screenSize.width > 800) {
      crossAxisCount = 3;
    } else if (screenSize.width > 600 || !isPortrait) {
      crossAxisCount = 2;
    } else {
      crossAxisCount = 2;
    }

    return GridView.builder(
      itemCount: menuItems.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: _getSpacing(screenSize),
        mainAxisSpacing: _getSpacing(screenSize),
        childAspectRatio: isOfflineMode ? 1.0 : _getAspectRatio(screenSize, isPortrait),
      ),
      itemBuilder: (context, index) => DashboardTile(
        title: menuItems[index]['title'] as String,
        iconData: menuItems[index]['icon'] as IconData,
        screen: menuItems[index]['route'] as Widget,
        availableOffline: menuItems[index]['availableOffline'] as bool,
        isOfflineMode: isOfflineMode,
        screenSize: screenSize,
      ),
    );
  }

  double _getPadding(Size screenSize) {
    if (screenSize.width > 1200) return 24.0;
    if (screenSize.width > 800) return 20.0;
    if (screenSize.width > 600) return 16.0;
    return 12.0;
  }

  double _getSpacing(Size screenSize) {
    if (screenSize.width > 1200) return 20.0;
    if (screenSize.width > 800) return 16.0;
    if (screenSize.width > 600) return 12.0;
    return 8.0;
  }

  double _getIconSize(Size screenSize) {
    if (screenSize.width > 1200) return 24.0;
    if (screenSize.width > 800) return 22.0;
    if (screenSize.width > 600) return 20.0;
    return 18.0;
  }

  double _getFontSize(Size screenSize, {bool isTitle = true}) {
    if (screenSize.width > 1200) return isTitle ? 18.0 : 16.0;
    if (screenSize.width > 800) return isTitle ? 16.0 : 14.0;
    if (screenSize.width > 600) return isTitle ? 14.0 : 13.0;
    return isTitle ? 12.0 : 11.0;
  }

  double _getAspectRatio(Size screenSize, bool isPortrait) {
    if (screenSize.width > 1200) return 1.2;
    if (screenSize.width > 800) return 1.1;
    if (!isPortrait) return 0.9;
    return 1.0;
  }
}

// Add this widget for reconnection
class _ReconnectScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Go Online')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Switch to Online Mode', style: TextStyle(fontSize: 18)),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => toggleOfflineMode(false),
              child: Text('Connect to Internet'),
            ),
          ],
        ),
      ),
    );
  }
}

// ... (keep your existing DashboardTile class)
class DashboardTile extends StatelessWidget {
  final String title;
  final IconData iconData;
  final Widget screen;
  final bool availableOffline;
  final bool isOfflineMode;
  final Size screenSize;

  const DashboardTile({
    super.key,
    required this.title,
    required this.iconData,
    required this.screen,
    required this.availableOffline,
    required this.isOfflineMode,
    required this.screenSize,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDisabled = isOfflineMode && !availableOffline;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isDisabled ? Colors.grey[300] : null,
      child: InkWell(
        onTap: isDisabled
            ? null
            : () => Navigator.push(context, MaterialPageRoute(builder: (context) => screen)),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.all(_getTilePadding()),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                children: [
                  Icon(
                    iconData,
                    size: _getTileIconSize(),
                    color: isDisabled ? Colors.grey : Colors.indigo,
                  ),
                  if (isDisabled)
                    Positioned(
                      right: 0,
                      child: Icon(Icons.wifi_off, size: _getSmallIconSize(), color: Colors.grey),
                    ),
                ],
              ),
              SizedBox(height: _getTileSpacing()),
              Flexible(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: _getTileFontSize(),
                    color: isDisabled ? Colors.grey : null,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isDisabled)
                Text(
                  'Offline',
                  style: TextStyle(
                    fontSize: _getSmallFontSize(), 
                    color: Colors.grey
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  double _getTilePadding() {
    if (screenSize.width > 1200) return 20.0;
    if (screenSize.width > 800) return 16.0;
    if (screenSize.width > 600) return 12.0;
    return 8.0;
  }

  double _getTileIconSize() {
    if (screenSize.width > 1200) return 48.0;
    if (screenSize.width > 800) return 40.0;
    if (screenSize.width > 600) return 36.0;
    return 32.0;
  }

  double _getSmallIconSize() {
    if (screenSize.width > 1200) return 20.0;
    if (screenSize.width > 800) return 18.0;
    if (screenSize.width > 600) return 16.0;
    return 14.0;
  }

  double _getTileSpacing() {
    if (screenSize.width > 1200) return 16.0;
    if (screenSize.width > 800) return 12.0;
    if (screenSize.width > 600) return 8.0;
    return 6.0;
  }

  double _getTileFontSize() {
    if (screenSize.width > 1200) return 16.0;
    if (screenSize.width > 800) return 14.0;
    if (screenSize.width > 600) return 12.0;
    return 11.0;
  }

  double _getSmallFontSize() {
    if (screenSize.width > 1200) return 12.0;
    if (screenSize.width > 800) return 11.0;
    if (screenSize.width > 600) return 10.0;
    return 9.0;
  }
}