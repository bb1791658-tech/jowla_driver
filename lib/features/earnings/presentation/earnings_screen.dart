import 'package:flutter/material.dart';
import 'package:jowla_driver/shared/widgets/backend_empty_state.dart';

/// لا يوجد في jowla_backend أي endpoint لأرباح السائق أو تقاريره
/// (وحدة analytics فارغة). تُعرض حالة صادقة بدل أرقام وهمية.
class EarningsScreen extends StatelessWidget {
  const EarningsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('الأرباح')),
        body: const BackendEmptyState(
          icon: Icons.bar_chart_rounded,
          title: 'تقارير الأرباح غير متوفرة حاليًا',
          message: 'لا يوفر خادم جولة الحالي واجهة لأرباح السائق. '
              'يظهر ملخص كل رحلة (الأجرة والعمولة والصافي) فور إكمالها.',
        ),
      );
}
