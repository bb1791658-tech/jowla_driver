import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../rides/presentation/ride_formatters.dart';
import '../data/backend_wallet_repository.dart';
import '../domain/models/driver_wallet.dart';

final driverWalletProvider = FutureProvider<DriverWallet>(
  (ref) => ref.watch(walletRepositoryProvider).currentWallet(),
);

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(driverWalletProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('المحفظة')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(driverWalletProvider.future),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            wallet.when(
              loading: () => const _WalletCard.loading(),
              error: (error, _) => _WalletErrorCard(
                onRetry: () => ref.invalidate(driverWalletProvider),
              ),
              data: (wallet) => _WalletCard(wallet: wallet),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({required this.wallet}) : isLoading = false;

  const _WalletCard.loading() : wallet = null, isLoading = true;

  final DriverWallet? wallet;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final amount = wallet == null ? '...' : '${formatIqd(wallet!.balance)} د.ع';
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      elevation: 1,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.account_balance_wallet_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              'الرصيد الحالي',
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              amount,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                color: colors.onSurface,
                fontSize: 34,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            if (isLoading) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(minHeight: 3),
            ],
          ],
        ),
      ),
    );
  }
}

class _WalletErrorCard extends StatelessWidget {
  const _WalletErrorCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded),
            const SizedBox(height: 12),
            const Text(
              'تعذر تحميل الرصيد من الخادم',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text('تأكد أن واجهة المحفظة مفعلة في الباك اند.'),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: onRetry,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}
