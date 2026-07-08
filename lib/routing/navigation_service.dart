import 'package:flutter/material.dart';

// Central navigation helper using global navigator key
class NavigationService {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  Future<dynamic>? push(Widget page) {
    return navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  void pop<T>([T? result]) {
    navigatorKey.currentState?.pop(result);
  }

  Future<dynamic>? pushReplacement(Widget page) {
    return navigatorKey.currentState?.pushReplacement(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  void popUntil(bool Function(Route<dynamic>) predicate) {
    navigatorKey.currentState?.popUntil(predicate);
  }
}
