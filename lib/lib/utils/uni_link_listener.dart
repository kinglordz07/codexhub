// lib/utils/app_link_listener.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';

class AppLinkListener {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;

  /// Call this in initState of your main widget
  void init(GlobalKey<NavigatorState> navigatorKey) {
    _handleInitialLink(navigatorKey);
    _listenToLinks(navigatorKey);
  }

  /// Dispose when no longer needed
  void dispose() {
    _sub?.cancel();
  }

  /// Handle cold start link
  Future<void> _handleInitialLink(GlobalKey<NavigatorState> navigatorKey) async {
    try {
      final Uri? initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _navigateToLink(navigatorKey, initialUri);
      }
    } catch (e) {
      debugPrint('Failed to get initial app link: $e');
    }
  }

  /// Listen to incoming links while app is running
  void _listenToLinks(GlobalKey<NavigatorState> navigatorKey) {
    _sub = _appLinks.uriLinkStream.listen(
      (Uri? uri) {
        if (uri != null) {
          _navigateToLink(navigatorKey, uri);
        }
      },
      onError: (err) {
        debugPrint('Failed to receive app link: $err');
      },
    );
  }

  /// Navigation logic based on link path
  void _navigateToLink(GlobalKey<NavigatorState> navigatorKey, Uri uri) {
    final context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint('Navigator context is null, cannot navigate to $uri');
      return;
    }

    debugPrint('Received app link: $uri');

    switch (uri.path) {
      case '/reset-password':
        final token = uri.queryParameters['token'];
        Navigator.pushNamed(
          context,
          '/reset-password',
          arguments: {'token': token},
        );
        break;
      case '/home':
        Navigator.pushNamed(context, '/home');
        break;
      default:
        debugPrint('Unknown link path, redirecting to /intro');
        Navigator.pushNamed(context, '/intro'); // fallback route
    }
  }
}
