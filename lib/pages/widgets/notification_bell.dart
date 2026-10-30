import 'package:flutter/material.dart';

import 'package:money_traker/constants/app_constants.dart';

class NotificationBell extends StatelessWidget {
  final int unreadCount;
  final VoidCallback onPressed;

  const NotificationBell({
    super.key,
    required this.unreadCount,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final arabic = Localizations.localeOf(context).languageCode == 'ar';
    return IconButton(
      tooltip: arabic ? 'الإشعارات' : 'Notifications',
      onPressed: onPressed,
      icon: Badge(
        isLabelVisible: unreadCount > 0,
        backgroundColor: AppConstants.errorColor,
        label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
        child: Icon(
          unreadCount > 0 ? Icons.notifications : Icons.notifications_outlined,
          color: unreadCount > 0 ? AppConstants.primaryColor : AppConstants.textSecondary,
        ),
      ),
    );
  }
}
