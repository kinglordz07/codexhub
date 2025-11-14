import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; 
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
import 'package:codexhub01/services/notif.dart';

// 🔹 App Links
import 'package:codexhub01/utils/uni_link_listener.dart';
import 'package:codexhub01/services/call_manager.dart';
import 'package:codexhub01/services/global_call_notification.dart'; 
import 'package:codexhub01/services/messageservice.dart';
import 'package:provider/provider.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
late final SupabaseClient supabase;
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);
bool isOfflineMode = false;

// 🔴 NOTIFICATION STATE MANAGEMENT
class NotificationState extends ChangeNotifier {
  int _pendingFriendRequests = 0;
  int _unreadMessages = 0;
  int _pendingSessions = 0;
  
  int get pendingFriendRequests => _pendingFriendRequests;
  int get unreadMessages => _unreadMessages;
  int get pendingSessions => _pendingSessions;
  
  bool get hasNotifications => _pendingFriendRequests > 0 || _unreadMessages > 0 || _pendingSessions > 0;
  
  void updateFriendRequests(int count) {
    _pendingFriendRequests = count;
    notifyListeners();
  }
  
  void updateUnreadMessages(int count) {
    _unreadMessages = count;
    notifyListeners();
  }
  
  void updatePendingSessions(int count) {
    _pendingSessions = count;
    notifyListeners();
  }
  
  void clearAll() {
    _pendingFriendRequests = 0;
    _unreadMessages = 0;
    _pendingSessions = 0;
    notifyListeners();
  }
}

final notificationState = NotificationState();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
   final basicNotificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;
  await NotificationService.initializeWithPreference(basicNotificationsEnabled);

  
  // 🔹 Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // 🔹 Load saved theme
  final isDark = prefs.getBool('isDarkMode') ?? false;
  themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;

  // 🔹 Check connectivity and initialize Supabase
  await initializeApp();

  final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();
  await notifications.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();

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
  final CallManager _callManager = CallManager(); 
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

    // Initialize call manager if online
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('📱 App initialized - waiting for user login to start call listener');
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = navigatorKey.currentContext;
      if (context != null && mounted) {
        _appLinkListener.init(navigatorKey);
        
        // Auto-redirect based on offline mode
        if (isOfflineMode) {
          Navigator.of(navigatorKey.currentContext!).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => DashboardScreenWrapper(callManager: _callManager)),
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
    _callManager.dispose(); 
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show loading screen while initializing
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

    return ChangeNotifierProvider(
      create: (context) => notificationState,
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: themeNotifier,
        builder: (context, themeMode, child) {
          return MaterialApp(
            title: 'CodeXHub',
            debugShowCheckedModeBanner: false,
            navigatorKey: navigatorKey,
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
            themeMode: themeMode,
            initialRoute: isOfflineMode ? '/dashboard' : '/intro',
            routes: {
              '/intro': (context) => const IntroScreen(),
              '/': (context) => const SignIn(),
              '/dashboard': (context) => DashboardScreenWrapper(callManager: _callManager),
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
      ),
    );
  }
}

// Dashboard Wrapper with Call Notification
class DashboardScreenWrapper extends StatefulWidget {
  final CallManager callManager;

  const DashboardScreenWrapper({super.key, required this.callManager});

  @override
  State<DashboardScreenWrapper> createState() => _DashboardScreenWrapperState();
}

class _DashboardScreenWrapperState extends State<DashboardScreenWrapper> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Main dashboard content
          DashboardScreen(),
          
          // Global call notification overlay
          GlobalCallNotification(callManager: widget.callManager),
        ],
      ),
    );
  }
}

Future<void> toggleOfflineMode(bool offline) async {
  isOfflineMode = offline;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('isOfflineMode', offline);
  
  // Force app rebuild
  if (navigatorKey.currentContext != null) {
    Navigator.of(navigatorKey.currentContext!).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => DashboardScreenWrapper(callManager: CallManager())),
      (route) => false,
    );
  }
}

// ---------- Responsive Dashboard WITH RED INDICATORS ----------

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  StreamSubscription? _callSub;
  RealtimeChannel? _friendRequestChannel; 
  RealtimeChannel? _messageChannel;
  bool _isUserLoggedIn = false;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  @override
void initState() {
  super.initState();
  
  _isUserLoggedIn = !isOfflineMode && (supabase.auth.currentUser != null);
  _loadDarkModePreference();

  if (_isUserLoggedIn && !isOfflineMode) {
    _loadUserThemePreference(); 
    _startNotificationListeners();
    _startNotificationCountListeners();
    
    // Force initial count load after a short delay
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(Duration(seconds: 1), () {
        _updateUnreadMessageCount();
        _updateFriendRequestCount();
      });
    });
  }

  _connectivitySubscription = Connectivity().onConnectivityChanged.listen((result) {
    final hasInternet = result.any((connectivity) => connectivity != ConnectivityResult.none);
    if (hasInternet && isOfflineMode) {
      _showReconnectionDialog();
    } else if (!hasInternet && !isOfflineMode) {
      toggleOfflineMode(true);
      _stopNotificationListeners();
    }
  });
}

// Add these methods to your _DashboardScreenState class

void _forceEnableNotifications() async {
  await NotificationService.updateNotificationPreference(true);
  
  // Force UI refresh
  if (mounted) {
    setState(() {});
  }
  
  // Refresh counts
  await _updateUnreadMessageCount();
  await _updateSessionCount();
}

  void _startNotificationCountListeners() {
    if (isOfflineMode) return;

    // Start listening for notification counts
    _listenForFriendRequestCounts();
    _listenForUnreadMessageCounts();
    _listenForSessionCounts();
  }

  void _listenForFriendRequestCounts() {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    _friendRequestChannel = supabase
        .channel('friend_request_counts')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'mentor_friend_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: userId,
          ),
          callback: (payload) async {
            await _updateFriendRequestCount();
          },
        )
        .subscribe();
  }

  

  void _listenForUnreadMessageCounts() {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return;

  _messageChannel = supabase
      .channel('unread_message_counts')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'mentor_messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'receiver_id',
          value: userId,
        ),
        callback: (payload) async {
          debugPrint('🔔 Message count changed - updating counts');
          await _updateUnreadMessageCount();
        },
      )
      .subscribe((status, error) {
    if (status == RealtimeSubscribeStatus.subscribed) {
      debugPrint('✅ Unread message count listener subscribed');
      // Load initial count immediately after subscription
      _updateUnreadMessageCount();
    }
  });
}

  void _listenForSessionCounts() {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return;

  // Add real session count listener if you have a sessions table
  // For now, we'll keep it disabled as per your original code
  debugPrint('ℹ️ Session count listener - implement based on your sessions table');
}

  Future<void> _updateFriendRequestCount() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final response = await supabase
          .from('mentor_friend_requests')
          .select()
          .eq('receiver_id', userId)
          .eq('status', 'pending');

      notificationState.updateFriendRequests(response.length);
    } catch (e) {
      debugPrint('❌ Error updating friend request count: $e');
    }
  }

  Future<void> _updateUnreadMessageCount() async {
  try {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      debugPrint('❌ No user ID for unread message count');
      return;
    }

    debugPrint('🔄 Fetching unread messages for user: $userId');
    
    final response = await supabase
        .from('mentor_messages')
        .select('id, sender_id, is_read')
        .eq('receiver_id', userId)
        .eq('is_read', false);

    debugPrint('📨 Found ${response.length} unread messages');
    
    if (mounted) {
      notificationState.updateUnreadMessages(response.length);
      debugPrint('✅ Updated unread message count: ${response.length}');
    }
  } catch (e) {
    debugPrint('❌ Error updating unread message count: $e');
  }
}

  Future<void> _updateSessionCount() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      final response = await supabase
          .from('mentor_sessions')
          .select()
          .eq('mentor_id', userId)
          .eq('status', 'pending');

      notificationState.updatePendingSessions(response.length);
    } catch (e) {
      debugPrint('❌ Error updating session count: $e');
    }
  }

  void _startNotificationListeners() {
    if (isOfflineMode) return;

    // Start message listener
    final messageService = MessageService();
    messageService.listenForNewMessages();

    // Start other notification listeners
    _listenForFriendRequests();
    _listenForSessionUpdates();

    // Load initial counts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateFriendRequestCount();
      _updateUnreadMessageCount();
      _updateSessionCount();
    });

    debugPrint('🔔 Notification listeners started');
  }

  void _stopNotificationListeners() {
    _friendRequestChannel?.unsubscribe();
    _friendRequestChannel = null;
    
    _messageChannel?.unsubscribe();
    _messageChannel = null;
    
    debugPrint('🔕 Notification listeners stopped (offline mode)');
  }

  // In _DashboardScreenState, modify notification listeners:

void _listenForFriendRequests() {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return;

  _friendRequestChannel = supabase
      .channel('mentor_friend_requests')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'mentor_friend_requests',
        callback: (payload) async {
          // 🔴 CHECK NOTIFICATION SETTING BEFORE SHOWING
          if (!NotificationService.shouldShowNotification()) {
            debugPrint('🔕 Notifications disabled - ignoring friend request');
            return;
          }
          
          final newRequest = payload.newRecord;
          final receiverId = newRequest['receiver_id']?.toString();
          
          if (receiverId == userId) {
            final senderId = newRequest['sender_id']?.toString();
            
            try {
              if (senderId == null) return;
              
              final senderProfile = await supabase
                  .from('profiles_new')
                  .select('username, role')
                  .eq('id', senderId)
                  .single();

              await NotificationService.showMentorFriendRequestNotification(
                fromUserName: senderProfile['username'] ?? 'Someone',
                fromUserRole: senderProfile['role'] ?? 'user',
              );
              
            } catch (e) {
              debugPrint('❌ Error getting sender profile: $e');
            }
          }
        },
      );
  _friendRequestChannel!.subscribe((status, error) {
    if (status == RealtimeSubscribeStatus.subscribed) {
      debugPrint('✅ Friend request listener subscribed');
    }
  });
}

  void _listenForSessionUpdates() {

    debugPrint('ℹ️ Session update listener disabled - using CallManager.IncomingCallListener instead');
  }

  Future<void> _loadDarkModePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('isDarkMode') ?? false;
    themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
  }

  Future<void> _loadUserThemePreference() async {
    if (isOfflineMode || !_isUserLoggedIn) return;
    
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final response = await supabase
            .from('profiles_new')
            .select('is_dark_mode')
            .eq('id', user.id)
            .single()
            .timeout(const Duration(seconds: 5));
        
        final userDarkMode = response['is_dark_mode'] as bool? ?? false;
        
        // Update theme based on user preference
        themeNotifier.value = userDarkMode ? ThemeMode.dark : ThemeMode.light;
        
        // Save to local preferences for offline use
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isDarkMode', userDarkMode);
        
        debugPrint('🎨 User theme preference loaded: ${userDarkMode ? 'Dark' : 'Light'}');
      }
    } catch (e) {
      debugPrint('❌ Error loading user theme preference: $e');
      // Fall back to local preference
      _loadDarkModePreference();
    }
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

              if (_isUserLoggedIn) {
                _loadUserThemePreference();
                _startNotificationListeners(); 
                _startNotificationCountListeners();
              }
            },
            child: Text('Go Online'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _callSub?.cancel();
    _connectivitySubscription.cancel();
    _friendRequestChannel?.unsubscribe();
    _messageChannel?.unsubscribe();
    super.dispose();
  }

  List<Map<String, dynamic>> get menuItems {
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
          'hasNotifications': false,
        },
        {
          'title': 'Go Online',
          'icon': Icons.wifi,
          'route': _ReconnectScreen(),
          'availableOffline': true,
          'hasNotifications': false,
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
        'hasNotifications': false,
      },
      {
        'title': 'Learning Tools',
        'icon': Icons.book_outlined,
        'route': LearningTools(),
        'availableOffline': true,
        'hasNotifications': false,
      },
    ];

    if (_isUserLoggedIn) {
      baseItems.addAll([
        {
          'title': 'Collaboration Lobby',
          'icon': Icons.group_work,
          'route': CollabLobbyScreen(),
          'availableOffline': false,
          'hasNotifications': false,
        },
        {
          'title': 'Friend List',
          'icon': Icons.people,
          'route': MentorFriendPage(),
          'availableOffline': false,
          'hasNotifications': true,
        },
        {
          'title': 'User Profile',
          'icon': Icons.account_circle,
          'route': ProfileScreen(themeNotifier: themeNotifier),
          'availableOffline': false,
          'hasNotifications': false,
        },
        {
          'title': 'Sessions Tabs',
          'icon': Icons.calendar_today,
          'route': SessionsTabScreen(),
          'availableOffline': false,
          'hasNotifications': true, 
        },
      ]);
    } else {
      baseItems.add({
        'title': 'Sign In',
        'icon': Icons.login,
        'route': const SignIn(),
        'availableOffline': false,
        'hasNotifications': false,
      });
    }

    return baseItems;
  }

  Widget _buildRedNotificationBadge(int count, {double size = 16}) {
    if (count <= 0) return SizedBox.shrink();
    
    return Container(
      padding: EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(size / 2),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withAlpha(128),
            blurRadius: 4,
            spreadRadius: 1,
          )
        ],
      ),
      constraints: BoxConstraints(
        minWidth: size,
        minHeight: size,
      ),
      child: Text(
        count > 99 ? '99+' : count.toString(),
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.6,
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildRedDotIndicator({double size = 8}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.red,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withAlpha(204),
            blurRadius: 4,
            spreadRadius: 1,
          )
        ],
      ),
    );
  }

 @override
Widget build(BuildContext context) {
  final screenSize = MediaQuery.of(context).size;
  final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
  
  return Consumer<NotificationState>(
    builder: (context, notificationState, child) {
      final bool showNotifications = NotificationService.areNotificationsAllowed;
      final bool shouldShowIndicators = showNotifications && notificationState.hasNotifications;
      
      return Scaffold(
        appBar: AppBar(
          title: const Text('CodeXHub Dashboard'),
          centerTitle: true,
          automaticallyImplyLeading: false,
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          actions: [
            // ENABLE NOTIFICATIONS BUTTON
            IconButton(
              icon: Icon(Icons.notifications_active, color: Colors.white),
              onPressed: _forceEnableNotifications,
              tooltip: 'Enable notifications',
            ),
            // 🔴 RED INDICATOR IN APP BAR
            if (shouldShowIndicators)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Stack(
                  children: [
                    Icon(Icons.notifications, color: Colors.white),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: _buildRedDotIndicator(size: 10),
                    ),
                  ],
                ),
              ),
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
                if (shouldShowIndicators && _isUserLoggedIn)
                  GestureDetector(
                    onTap: _showNotificationSummary,
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(_getSpacing(screenSize)),
                      margin: EdgeInsets.only(bottom: _getSpacing(screenSize)),
                      decoration: BoxDecoration(
                        color: Colors.red.withAlpha(30),
                        border: Border.all(color: Colors.red),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.notifications_active, color: Colors.red, size: _getIconSize(screenSize)),
                          SizedBox(width: _getSpacing(screenSize)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'You have new notifications',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: _getFontSize(screenSize, isTitle: false)
                                  ),
                                ),
                                SizedBox(height: 4),
                                Row(
                                  children: [
                                    if (notificationState.pendingFriendRequests > 0)
                                      _buildNotificationSummaryChip(
                                        '${notificationState.pendingFriendRequests} Friend Requests',
                                        Colors.blue,
                                      ),
                                    if (notificationState.unreadMessages > 0)
                                      _buildNotificationSummaryChip(
                                        '${notificationState.unreadMessages} Unread Messages',
                                        Colors.green,
                                      ),
                                    if (notificationState.pendingSessions > 0)
                                      _buildNotificationSummaryChip(
                                        '${notificationState.pendingSessions} Pending Sessions',
                                        Colors.orange,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios, color: Colors.red, size: _getIconSize(screenSize)),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: _buildGrid(screenSize, isPortrait, notificationState, showNotifications),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

  Widget _buildNotificationSummaryChip(String text, Color color) {
    return Container(
      margin: EdgeInsets.only(right: 8),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
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
                        MaterialPageRoute(builder: (context) => SessionsTabScreen()),
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

  Widget _buildGrid(Size screenSize, bool isPortrait, NotificationState notificationState, bool showNotifications) {
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
      hasNotifications: menuItems[index]['hasNotifications'] as bool,
      notificationState: notificationState,
      buildRedNotificationBadge: _buildRedNotificationBadge,
      buildRedDotIndicator: _buildRedDotIndicator,
      showNotifications: showNotifications,
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

class DashboardTile extends StatelessWidget {
  final String title;
  final IconData iconData;
  final Widget screen;
  final bool availableOffline;
  final bool isOfflineMode;
  final Size screenSize;
  final bool hasNotifications;
  final NotificationState notificationState;
  final Widget Function(int, {double size}) buildRedNotificationBadge;
  final Widget Function({double size}) buildRedDotIndicator;
  final bool showNotifications;

  const DashboardTile({
    super.key,
    required this.title,
    required this.iconData,
    required this.screen,
    required this.availableOffline,
    required this.isOfflineMode,
    required this.screenSize,
    required this.hasNotifications,
    required this.notificationState,
    required this.buildRedNotificationBadge,
    required this.buildRedDotIndicator,
    required this.showNotifications,
  });

  int get _notificationCount {
  if (!hasNotifications) return 0;
  
  int count = 0;
  
  if (title == 'Friend List') {
    count = notificationState.pendingFriendRequests + notificationState.unreadMessages;
    debugPrint('🔔 Friend List notifications: $count (requests: ${notificationState.pendingFriendRequests}, messages: ${notificationState.unreadMessages})');
  } else if (title == 'Sessions Tabs') {
    count = notificationState.pendingSessions;
    debugPrint('🔔 Sessions notifications: $count');
  }
  
  return count;
}

bool get _showNotifications {
  final bool shouldShow = showNotifications && hasNotifications && _notificationCount > 0;
  return shouldShow;
}

  @override
  Widget build(BuildContext context) {
    final bool isDisabled = isOfflineMode && !availableOffline;

    return Card(
      elevation: _showNotifications ? 4 : 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isDisabled ? Colors.grey[300] : (_showNotifications ? Colors.blue.shade50 : null),
      child: InkWell(
        onTap: isDisabled
            ? null
            : () => Navigator.push(context, MaterialPageRoute(builder: (context) => screen)),
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // MAIN CONTENT - PROPERLY CENTERED
            Container(
              width: double.infinity,
              height: double.infinity,
              padding: EdgeInsets.all(_getTilePadding()),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center, // This centers vertically
                crossAxisAlignment: CrossAxisAlignment.center, // This centers horizontally
                children: [
                  Stack(
                    children: [
                      Icon(
                        iconData,
                        size: _getTileIconSize(),
                        color: isDisabled ? Colors.grey : (_showNotifications ? Colors.indigo : Colors.indigo),
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
                        color: isDisabled ? Colors.grey : (_showNotifications ? Colors.indigo : null),
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
            // 🔴 RED NOTIFICATION INDICATOR - Positioned absolutely
            if (_showNotifications)
              Positioned(
                top: 8,
                right: 8,
                child: _notificationCount > 1 
                    ? buildRedNotificationBadge(_notificationCount, size: 20)
                    : buildRedDotIndicator(size: 12),
              ),
          ],
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