import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/jowla_image_provider.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/models/driver_session.dart';
import '../../driver/data/backend_driver_repository.dart';
import '../../driver/domain/models/driver_account.dart';

/// بيانات حقيقية من GET /drivers/me.
final driverAccountProvider = FutureProvider.autoDispose<DriverAccount>((ref) {
  ref.watch(authSessionProvider);
  return ref.watch(driverRepositoryProvider).me();
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(authSessionProvider, (_, _) {
      ref.invalidate(driverAccountProvider);
    });
    final account = ref.watch(driverAccountProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('حسابي')),
      body: account.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(error.toString(), textAlign: TextAlign.center),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(driverAccountProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ),
        data: (data) => _ProfileBody(account: data),
      ),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody({required this.account});

  final DriverAccount account;

  @override
  Widget build(BuildContext context) {
    final profile = account.profile;
    final status = profile.status;
    final vehicle = account.activeVehicle;
    final profilePhoto = jowlaImageProvider(profile.photoUrl);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundImage: profilePhoto,
                  child: profilePhoto == null
                      ? const Icon(Icons.person_rounded, size: 36)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        profile.phone,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.right,
                      ),
                    ],
                  ),
                ),
                if (status != null)
                  Chip(
                    label: Text(status.arabicLabel),
                    backgroundColor: status.canWork
                        ? Colors.green.withValues(alpha: .12)
                        : Theme.of(context).colorScheme.errorContainer,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.directions_car_rounded),
            title: const Text('المركبة'),
            subtitle: Text(
              vehicle == null
                  ? 'لا توجد مركبة نشطة مسجلة لدى جولة'
                  : '${vehicle.summary}\nرقم اللوحة: ${vehicle.plateNumber}',
            ),
            isThreeLine: vehicle != null,
          ),
        ),
        if (account.serviceNames.isNotEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.category_rounded),
              title: const Text('الخدمات المفعلة'),
              subtitle: Text(
                account.serviceNames
                    .where((name) => name.isNotEmpty)
                    .join('، '),
              ),
            ),
          ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.folder_copy_rounded),
            title: const Text('المستندات'),
            subtitle: const Text('الهوية، الإجازة واستمارة السيارة'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => context.push('/documents'),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.account_balance_wallet_rounded),
            title: const Text('المحفظة'),
            subtitle: const Text('الرصيد والحركات المالية'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => context.push('/wallet'),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.settings_rounded),
            title: const Text('الإعدادات'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => context.push('/settings'),
          ),
        ),
      ],
    );
  }
}
