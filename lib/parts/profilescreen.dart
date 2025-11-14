import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:codexhub01/parts/log_in.dart';
import 'package:codexhub01/services/notif.dart';
import '../main.dart'; 

class ProfileScreen extends StatefulWidget {
  final ValueNotifier<ThemeMode>? themeNotifier;

  const ProfileScreen({super.key, this.themeNotifier});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool isDarkMode = false;
  bool notificationsEnabled = false;
  String? profileImageUrl;
  String userName = "Loading...";
  String email = "Loading...";
  SharedPreferences? _prefs;

  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _initializePreferences();
    _loadUserProfile();
    _checkFirstTimeNotification();
  }

  Future<void> _checkFirstTimeNotification() async {
    _prefs ??= await SharedPreferences.getInstance();
    final hasSeenPrompt = _prefs?.getBool('hasSeenNotificationPrompt') ?? false;
    
    if (!hasSeenPrompt && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showNotificationExplanationDialog();
      });
    }
  }

  void _showNotificationExplanationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Enable Notifications"),
        content: const Text(
          "Get notified about:\n"
          "• New messages and calls\n"
          "• Session requests and updates\n" 
          "• Live coding invitations\n"
          "• Friend requests\n"
          "• Important announcements\n\n"
          "You can always change this in settings.",
        ),
        actions: [
          TextButton(
            onPressed: () {
              _prefs?.setBool('hasSeenNotificationPrompt', true);
              _prefs?.setBool('notificationsEnabled', false);
              Navigator.pop(context);
            },
            child: const Text("Not Now"),
          ),
          TextButton(
            onPressed: () {
              _prefs?.setBool('hasSeenNotificationPrompt', true);
              _prefs?.setBool('notificationsEnabled', true);
              setState(() {
                notificationsEnabled = true;
              });
              
              NotificationService.showNotification(
                title: "Notifications Enabled!",
                body: "You'll now receive alerts for important updates.",
              );
              
              _updateNotificationPreference(true);
              
              Navigator.pop(context);
            },
            child: const Text("Enable"),
          ),
        ],
      ),
    );
  }

  Future<void> _initializePreferences() async {
    _prefs = await SharedPreferences.getInstance();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    _prefs ??= await SharedPreferences.getInstance();

    if (!mounted) return;
    setState(() {
      isDarkMode = _prefs?.getBool('isDarkMode') ?? false;
      notificationsEnabled = _prefs?.getBool('notificationsEnabled') ?? true;
    });
    
    if (widget.themeNotifier != null) {
      widget.themeNotifier!.value = isDarkMode ? ThemeMode.dark : ThemeMode.light;
    }
  }

  Future<void> _loadUserProfile() async {
  final user = supabase.auth.currentUser;
  if (user == null) return;

  final userEmail = user.email ?? "unknown@example.com";

  try {
    final response = await supabase
        .from('profiles_new')
        .select('username, avatar_url, is_dark_mode, role, notifications_enabled')
        .eq('id', user.id)
        .maybeSingle();

    if (!mounted) return;

    if (response != null) {
      String? avatar = response['avatar_url'] as String?;
      if (avatar != null && avatar.isNotEmpty) {
        avatar = "$avatar?t=${DateTime.now().millisecondsSinceEpoch}";
      }
      
      bool userDarkMode = response['is_dark_mode'] as bool? ?? false;
      bool userNotificationsEnabled = response['notifications_enabled'] as bool? ?? true;

      setState(() {
        userName = response['username'] ?? "User";
        email = userEmail;
        profileImageUrl = avatar;
        isDarkMode = userDarkMode;
        notificationsEnabled = userNotificationsEnabled;
      });

      // 🔴 FIX: Update local preferences with user's database preference
      await _updateLocalPreferences(userDarkMode, userNotificationsEnabled);
    }
  } catch (e) {
    debugPrint("Error loading user profile: $e");
    _loadPreferences();
  }
}

Future<void> _updateLocalPreferences(bool darkMode, bool notifications) async {
  _prefs ??= await SharedPreferences.getInstance();
  await _prefs?.setBool('isDarkMode', darkMode);
  await _prefs?.setBool('notificationsEnabled', notifications);
  
  // Update NotificationService with user's preference
  NotificationService.updateNotificationPreference(notifications);
  
  if (widget.themeNotifier != null) {
    widget.themeNotifier!.value = darkMode ? ThemeMode.dark : ThemeMode.light;
  }
}

  Future<void> _toggleDarkMode(bool value) async {
    if (!mounted) return;
    
    setState(() => isDarkMode = value);
    await _updateThemePreferences(value);
  }

  Future<void> _updateThemePreferences(bool value) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs?.setBool('isDarkMode', value);

    widget.themeNotifier?.value = value ? ThemeMode.dark : ThemeMode.light;

    final user = supabase.auth.currentUser;
    if (user != null) {
      try {
        await supabase
            .from('profiles_new')
            .update({'is_dark_mode': value})
            .eq('id', user.id);
        debugPrint("✅ Dark mode preference updated: $value");
      } catch (e) {
        debugPrint("❌ Error updating dark mode: $e");
      }
    }
  }

  Future<void> _toggleNotifications(bool value) async {
  if (!mounted) return;
  
  setState(() => notificationsEnabled = value);
  
  try {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs?.setBool('notificationsEnabled', value);
    
    // 🔔 CRITICAL: Update NotificationService preference
    NotificationService.updateNotificationPreference(value);

    if (value) {
      await NotificationService.initialize();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Notifications enabled"),
          ),
        );
      }
      _restartNotificationListeners();
    } else {
      await NotificationService.cancelAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Notifications disabled"),
          ),
        );
      }
      _clearNotificationIndicators();
    }

    // 🔴 FIX: Store preference in database for THIS USER
    await _updateNotificationPreference(value);

  } catch (e) {
    debugPrint("Error updating notifications: $e");
    if (mounted) {
      setState(() => notificationsEnabled = !value);
    }
  }
}

Future<void> _updateNotificationPreference(bool value) async {
  final user = supabase.auth.currentUser;
  if (user != null) {
    try {
      await supabase
          .from('profiles_new')
          .update({'notifications_enabled': value})
          .eq('id', user.id);
      debugPrint("✅ Notification preference updated for user ${user.id}: $value");
    } catch (e) {
      debugPrint("❌ Error updating notification preference: $e");
    }
  }
}

void _restartNotificationListeners() {
  // This will be handled by the dashboard's initState
  // Force a rebuild of the dashboard to restart listeners
  if (mounted) {
    // You might want to use a more robust state management approach here
    // For now, we'll rely on the dashboard detecting the preference change
  }
}

void _clearNotificationIndicators() {
  // Clear all notification counts and indicators
  notificationState.clearAll();
}

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Confirm Logout"),
          content: const Text("Are you sure you want to log out?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("No"),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _logout();
              },
              child: const Text("Yes"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _logout() async {
    await supabase.auth.signOut();

    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const SignIn()),
        (route) => false,
      );
    }
  }

  void _editProfile() {
    showDialog(
      context: context,
      builder: (context) => EditProfileDialog(
        currentUsername: userName,
        currentAvatarUrl: profileImageUrl,
        onSave: _handleProfileUpdate,
      ),
    );
  }

  Future<void> _handleProfileUpdate({
    required String newUsername,
    required XFile? newAvatar,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final Map<String, dynamic> updateData = {'username': newUsername};

      if (newAvatar != null) {
        try {
          final bytes = await newAvatar.readAsBytes();
          final fileExt = newAvatar.path.split('.').last.toLowerCase();
          final fileName = '${user.id}.${fileExt == 'jpg' ? 'jpeg' : fileExt}';

          await supabase.storage
              .from('avatars')
              .uploadBinary(
                fileName,
                bytes,
                fileOptions: const FileOptions(upsert: true),
              );

          final publicUrl = supabase.storage
              .from('avatars')
              .getPublicUrl(fileName);

          updateData['avatar_url'] = publicUrl;
        } catch (e) {
          debugPrint("❌ Error uploading avatar: $e");
        }
      }

      await supabase.from('profiles_new').update(updateData).eq('id', user.id);

      await _loadUserProfile();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Profile updated successfully!")),
        );
      }
    } catch (e) {
      debugPrint("❌ Error updating profile: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Error updating profile")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile Settings'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadUserProfile,
            tooltip: "Refresh profile",
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Profile Header Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (profileImageUrl != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FullScreenProfilePic(
                                imageUrl: profileImageUrl,
                              ),
                            ),
                          );
                        }
                      },
                      child: Hero(
                        tag: "profilePicHero",
                        child: CircleAvatar(
                          radius: 40,
                          backgroundColor: Colors.grey[300],
                          backgroundImage: profileImageUrl != null
                              ? NetworkImage(profileImageUrl!)
                              : null,
                          child: profileImageUrl == null
                              ? const Icon(Icons.account_circle, size: 70, color: Colors.grey)
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userName,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            email,
                            style: TextStyle(
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Settings Card
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.dark_mode),
                    title: const Text("Dark Mode"),
                    trailing: Switch(
                      value: isDarkMode,
                      onChanged: _toggleDarkMode,
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.notifications),
                    title: const Text("Notifications"),
                    trailing: Switch(
                      value: notificationsEnabled,
                      onChanged: _toggleNotifications,
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.edit),
                    title: const Text("Edit Profile"),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: _editProfile,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Logout Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _confirmLogout(context),
                icon: const Icon(Icons.logout),
                label: const Text("Log Out"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[50],
                  foregroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EditProfileDialog extends StatefulWidget {
  final String currentUsername;
  final String? currentAvatarUrl;
  final Function({required String newUsername, required XFile? newAvatar}) onSave;

  const EditProfileDialog({
    super.key,
    required this.currentUsername,
    this.currentAvatarUrl,
    required this.onSave,
  });

  @override
  State<EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<EditProfileDialog> {
  final TextEditingController _usernameController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedAvatar;
  Uint8List? _avatarBytes;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _usernameController.text = widget.currentUsername;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 800,
        maxHeight: 800,
      );

      if (pickedFile != null && mounted) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _selectedAvatar = pickedFile;
          _avatarBytes = bytes;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to pick image: $e")),
        );
      }
    }
  }

  Future<void> _saveProfile() async {
    final newUsername = _usernameController.text.trim();

    if (newUsername.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Username cannot be empty")),
        );
      }
      return;
    }

    if (mounted) {
      setState(() => _isSaving = true);
    }

    try {
      await widget.onSave(newUsername: newUsername, newAvatar: _selectedAvatar);

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${e.toString()}")),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  ImageProvider? _getAvatarImage() {
    if (_avatarBytes != null) {
      return MemoryImage(_avatarBytes!);
    } else if (widget.currentAvatarUrl != null) {
      return NetworkImage(widget.currentAvatarUrl!);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    return AlertDialog(
      title: Text(
        "Edit Profile",
        style: TextStyle(fontSize: isSmallScreen ? 18 : 20),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Avatar Section
            Column(
              children: [
                GestureDetector(
                  onTap: _pickImage,
                  child: CircleAvatar(
                    radius: isSmallScreen ? 40 : 50,
                    backgroundColor: Colors.grey[300],
                    backgroundImage: _getAvatarImage(),
                    child: _getAvatarImage() == null
                        ? Icon(
                            Icons.camera_alt,
                            size: isSmallScreen ? 30 : 40,
                            color: Colors.grey,
                          )
                        : null,
                  ),
                ),
                SizedBox(height: isSmallScreen ? 6 : 8),
                TextButton.icon(
                  onPressed: _pickImage,
                  icon: Icon(
                    Icons.edit,
                    size: isSmallScreen ? 18 : 20,
                  ),
                  label: Text(
                    "Change Photo",
                    style: TextStyle(fontSize: isSmallScreen ? 14 : 16),
                  ),
                ),
              ],
            ),
            SizedBox(height: isSmallScreen ? 16 : 20),

            // Username Field
            TextField(
              controller: _usernameController,
              decoration: InputDecoration(
                labelText: "Username",
                border: const OutlineInputBorder(),
                prefixIcon: Icon(
                  Icons.person,
                  size: isSmallScreen ? 20 : 24,
                ),
              ),
              style: TextStyle(fontSize: isSmallScreen ? 14 : 16),
            ),
            SizedBox(height: isSmallScreen ? 8 : 10),

          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: Text(
            "Cancel",
            style: TextStyle(fontSize: isSmallScreen ? 14 : 16),
          ),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _saveProfile,
          child: _isSaving
              ? SizedBox(
                  height: isSmallScreen ? 18 : 20,
                  width: isSmallScreen ? 18 : 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  "Save",
                  style: TextStyle(fontSize: isSmallScreen ? 14 : 16),
                ),
        ),
      ],
    );
  }
}

class FullScreenProfilePic extends StatelessWidget {
  final String? imageUrl;

  const FullScreenProfilePic({super.key, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Center(
          child: Hero(
            tag: "profilePicHero",
            child: imageUrl != null
                ? Image.network(
                    imageUrl!,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(
                        Icons.error,
                        size: isSmallScreen ? 80 : 100,
                        color: Colors.white54,
                      );
                    },
                  )
                : Icon(
                    Icons.account_circle,
                    size: isSmallScreen ? 150 : 200,
                    color: Colors.white54,
                  ),
          ),
        ),
      ),
    );
  }
}