import 'package:flutter/material.dart';

import '../../../utils/constant.dart';

// Circular default banner image for caller avatars
class DefaultCallerAvatar extends StatelessWidget {
  const DefaultCallerAvatar({
    super.key,
    this.size = 88,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.asset(
        AppConstants.defaultCallerBanner,
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}
