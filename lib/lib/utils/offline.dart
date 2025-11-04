import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class OfflineManager {
  static final OfflineManager _instance = OfflineManager._internal();
  factory OfflineManager() => _instance;
  OfflineManager._internal();

  static const String _offlineCodeKey = 'offline_code';
  static const String _offlineLanguageKey = 'offline_language';
  static const String _offlineFilesKey = 'offline_files';

  // Check connectivity
  Future<bool> checkConnectivity() async {
    try {
      final List<ConnectivityResult> connectivity = await Connectivity().checkConnectivity();
      
      // We're offline only if we have NO connectivity options
      return connectivity.isEmpty || connectivity.contains(ConnectivityResult.none);
    } catch (e) {
      return true; // Assume offline if connectivity check fails
    }
  }

  // Enhanced internet connection check
  Future<bool> hasInternetConnection() async {
    try {
      // Method 1: Try DNS lookup
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    } on TimeoutException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  // Save code locally
  Future<void> saveCodeLocally(String code, String language) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_offlineCodeKey, code);
      await prefs.setString(_offlineLanguageKey, language);
      _debugPrint('💾 Code saved locally for offline use');
    } catch (e) {
      _debugPrint('❌ Failed to save code locally: $e');
    }
  }

  // Load code locally
  Future<Map<String, String>> loadCodeLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        'code': prefs.getString(_offlineCodeKey) ?? '',
        'language': prefs.getString(_offlineLanguageKey) ?? 'python',
      };
    } catch (e) {
      _debugPrint('❌ Failed to load local code: $e');
      return {'code': '', 'language': 'python'};
    }
  }

  // Save multiple files
  Future<void> saveOfflineFiles(List<Map<String, dynamic>> files) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final filesJson = files.map((file) => {
        'title': file['title'] ?? 'Untitled',
        'code': file['code'] ?? '',
        'language': file['language'] ?? 'python',
        'timestamp': file['timestamp'] ?? DateTime.now().toString(),
      }).toList();
      await prefs.setString(_offlineFilesKey, jsonEncode(filesJson));
      _debugPrint('💾 ${files.length} files saved for offline use');
    } catch (e) {
      _debugPrint('❌ Failed to save offline files: $e');
    }
  }

  // Load multiple files
  Future<List<Map<String, dynamic>>> loadOfflineFiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final filesJson = prefs.getString(_offlineFilesKey);
      if (filesJson != null && filesJson.isNotEmpty) {
        final files = jsonDecode(filesJson) as List;
        return files.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      _debugPrint('❌ Failed to load offline files: $e');
      return [];
    }
  }

  // Clear all offline data
  Future<void> clearAllOfflineData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_offlineCodeKey);
      await prefs.remove(_offlineLanguageKey);
      await prefs.remove(_offlineFilesKey);
      _debugPrint('🗑️ All offline data cleared');
    } catch (e) {
      _debugPrint('❌ Failed to clear offline data: $e');
    }
  }

  // Get offline storage info
  Future<Map<String, dynamic>> getStorageInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_offlineCodeKey);
      final filesJson = prefs.getString(_offlineFilesKey);
      final files = filesJson != null ? jsonDecode(filesJson) as List : [];
      
      return {
        'hasCode': code != null && code.isNotEmpty,
        'codeLength': code?.length ?? 0,
        'fileCount': files.length,
        'lastUpdated': DateTime.now().toString(),
      };
    } catch (e) {
      return {
        'hasCode': false,
        'codeLength': 0,
        'fileCount': 0,
        'lastUpdated': DateTime.now().toString(),
      };
    }
  }

  // Monitor connectivity changes
  Stream<bool> get connectivityStream {
    return Connectivity().onConnectivityChanged.map((List<ConnectivityResult> results) {
      return results.isEmpty || results.contains(ConnectivityResult.none);
    });
  }

  // Private debug print method
  void _debugPrint(String message) {
    (message);
  }
}