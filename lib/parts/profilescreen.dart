import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:codexhub01/parts/log_in.dart';

class ProfileScreen extends StatefulWidget {
  final ValueNotifier<ThemeMode>? themeNotifier;

  const ProfileScreen({super.key, this.themeNotifier});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with WidgetsBindingObserver {
  bool isDarkMode = false;
  bool notificationsEnabled = false;
  String? profileImageUrl;
  String userName = "Loading...";
  String email = "Loading...";
  SharedPreferences? _prefs;

  final supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  Future<void> pickImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      // do something with pickedFile
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializePreferences();
    _loadUserProfile();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
  }

  Future<void> _loadUserProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final userEmail = user.email ?? "unknown@example.com";

    try {
      final response =
          await supabase
              .from('profiles')
              .select('username, avatar_url')
              .eq('id', user.id)
              .maybeSingle();

      if (!mounted) return;

      String? avatar;
      if (response != null) {
        avatar = response['avatar_url'] as String?;
        if (avatar != null && avatar.isNotEmpty) {
          avatar = "$avatar?t=${DateTime.now().millisecondsSinceEpoch}";
        }

        setState(() {
          userName = response['username'] ?? "User";
          email = userEmail;
          profileImageUrl = avatar;
        });
      } else {
        await _createBasicProfile(user, userEmail);
      }
    } catch (e) {
      debugPrint("Error loading user profile: $e");
      if (e.toString().contains('avatar_url')) {
        await _createBasicProfile(user, userEmail);
      }
    }
  }

  Future<void> _createBasicProfile(User user, String userEmail) async {
    try {
      await supabase.from('profiles').insert({
        'id': user.id,
        'username': user.email?.split('@').first ?? 'User',
        'email': userEmail,
        'role': 'user',
        'created_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        setState(() {
          userName = user.email?.split('@').first ?? 'User';
          email = userEmail;
        });
      }
    } catch (e) {
      debugPrint("Error creating basic profile: $e");
    }
  }

  Future<void> _toggleDarkMode(bool value) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs?.setBool('isDarkMode', value);

    if (!mounted) return;
    setState(() => isDarkMode = value);

    widget.themeNotifier?.value = value ? ThemeMode.dark : ThemeMode.light;
  }

  Future<void> _toggleNotifications(bool value) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs?.setBool('notificationsEnabled', value);

    if (!mounted) return;
    setState(() => notificationsEnabled = value);
  }

  void _confirmLogout(BuildContext context) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text("Confirm Logout"),
          content: const Text("Are you sure you want to log out?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("No"),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
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

  // Safe snackbar method
  void _safeShowSnackBar(String message, {bool isError = false}) {
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: isError ? Colors.red : Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      });
    }
  }

  void _editProfile() {
    if (!mounted) return;

    showDialog(
      context: context,
      builder:
          (context) => EditProfileDialog(
            currentUsername: userName,
            currentAvatarUrl: profileImageUrl,
            onSave: _handleProfileUpdate,
            currentRole: '',
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

      // Handle avatar upload if a new image was selected
      if (newAvatar != null) {
        try {
          debugPrint("🖼️ Starting avatar upload...");

          final bytes = await newAvatar.readAsBytes();
          final fileExt = newAvatar.path.split('.').last.toLowerCase();
          final fileName = '${user.id}.${fileExt == 'jpg' ? 'jpeg' : fileExt}';

          debugPrint("📁 Uploading file: $fileName");

          // Upload to Supabase Storage
          await supabase.storage
              .from('avatars')
              .uploadBinary(
                fileName,
                bytes,
                fileOptions: const FileOptions(upsert: true),
              );

          debugPrint("✅ Avatar uploaded successfully");

          // Get public URL
          final publicUrl = supabase.storage
              .from('avatars')
              .getPublicUrl(fileName);

          debugPrint("🔗 Avatar URL: $publicUrl");

          updateData['avatar_url'] = publicUrl;
        } catch (e) {
          debugPrint("❌ Error uploading avatar: $e");
          _safeShowSnackBar("Failed to upload image: $e", isError: true);
          // Continue without avatar if upload fails
        }
      }

      // Update profile in database
      debugPrint("💾 Updating profile...");
      await supabase.from('profiles').update(updateData).eq('id', user.id);

      debugPrint("✅ Profile updated successfully");

      // Reload profile to reflect changes
      await _loadUserProfile();

      _safeShowSnackBar("Profile updated successfully!");
    } catch (e) {
      debugPrint("❌ Error updating profile: $e");
      _safeShowSnackBar(
        "Error updating profile: ${e.toString()}",
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile Settings'),
        backgroundColor: Colors.indigo,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadUserProfile,
            tooltip: "Refresh profile",
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      if (profileImageUrl != null && mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (_) => FullScreenProfilePic(
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
                        backgroundImage:
                            profileImageUrl != null
                                ? NetworkImage(profileImageUrl!)
                                : null,
                        child:
                            profileImageUrl == null
                                ? const Icon(
                                  Icons.account_circle,
                                  size: 70,
                                  color: Colors.grey,
                                )
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
                        Text(
                          email,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

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

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                if (mounted) _confirmLogout(context);
              },
              icon: const Icon(Icons.logout),
              label: const Text("Log Out"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[50],
                foregroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Separate dialog widget
class EditProfileDialog extends StatefulWidget {
  final String currentUsername;
  final String currentRole;
  final String? currentAvatarUrl;
  final Function({required String newUsername, required XFile? newAvatar})
  onSave;

  const EditProfileDialog({
    super.key,
    required this.currentUsername,
    required this.currentRole,
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to pick image: $e")));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: ${e.toString()}")));
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
    return AlertDialog(
      title: const Text("Edit Profile"),
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
                    radius: 50,
                    backgroundColor: Colors.grey[300],
                    backgroundImage: _getAvatarImage(),
                    child:
                        _getAvatarImage() == null
                            ? const Icon(
                              Icons.camera_alt,
                              size: 40,
                              color: Colors.grey,
                            )
                            : null,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.edit),
                  label: const Text("Change Photo"),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Username Field
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: "Username",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 10),

            // Role Display
            Text(
              "Role: ${widget.currentRole}",
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _saveProfile,
          child:
              _isSaving
                  ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Text("Save"),
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: Hero(
          tag: "profilePicHero",
          child:
              imageUrl != null
                  ? Image.network(
                    imageUrl!,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(
                        Icons.error,
                        size: 100,
                        color: Colors.white54,
                      );
                    },
                  )
                  : const Icon(
                    Icons.account_circle,
                    size: 200,
                    color: Colors.white54,
                  ),
        ),
      ),
    );
  }
}
