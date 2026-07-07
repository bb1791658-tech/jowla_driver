import 'package:flutter/material.dart';
import 'package:jowla_driver/shared/widgets/backend_empty_state.dart';

/// لا يوجد في jowla_backend أي endpoint للمحفظة أو الرصيد.
class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('المحفظة')),
        body: const BackendEmptyState(
          icon: Icons.account_balance_wallet_outlined,
          title: 'المحفظة غير متوفرة حاليًا',
          message: 'لا يوفر خادم جولة الحالي واجهة للمحفظة أو الرصيد. '
              'الدفع الحالي نقدي ويُسلّم مباشرة للسائق.',
        ),
      );
}
