import 'package:flutter/material.dart';
import 'package:jowla_driver/shared/widgets/backend_empty_state.dart';

/// إشعارات Backend الحالية هي Push فقط (notifications.service.ts يرسل عبر
/// FCM/Mock ويخزن سجل NotificationLog) ولا يوجد endpoint لقراءة القائمة.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('الإشعارات')),
        body: const BackendEmptyState(
          icon: Icons.notifications_none_rounded,
          title: 'لا توجد قائمة إشعارات',
          message: 'يرسل خادم جولة الإشعارات دفعًا (Push) فقط حاليًا، '
              'ولا يوفر واجهة لعرض سجل الإشعارات داخل التطبيق.',
        ),
      );
}
