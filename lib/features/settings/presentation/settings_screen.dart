import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('الإعدادات')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Card(
              child: ListTile(
                leading: Icon(Icons.language_rounded),
                title: Text('اللغة'),
                trailing: Text('العربية'),
              ),
            ),
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline_rounded),
                title: Text('حول التطبيق'),
                subtitle: Text('جولة للسائق — الإصدار 1.0.0'),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () async {
                // تسجيل الخروج الحقيقي: DELETE /auth/sessions/current
                // ثم مسح الجلسة محليًا؛ الراوتر يعيد التوجيه إلى /login.
                await ref.read(authSessionProvider.notifier).logout();
              },
              icon: const Icon(Icons.logout_rounded),
              label: const Text('تسجيل الخروج'),
            ),
          ],
        ),
      );
}
