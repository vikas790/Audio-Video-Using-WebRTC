import 'package:flutter/material.dart';

import 'permission_helper.dart';

// Shared SnackBar + settings dialog for permission flows
class PermissionUi {
  PermissionUi._();

  static void showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  static Future<void> showSettingsDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              PermissionHelper.openSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}
