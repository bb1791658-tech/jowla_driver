import 'package:flutter/material.dart';

/// لا توجد في jowla_backend حاليًا أي مسارات لرفع مستندات السائق
/// (وحدة media بلا Controller، ولا يوجد أي endpoint من نوع
/// documents/upload في Swagger). عرض حالة صادقة أفضل من اختراع عقد.
class DocumentsScreen extends StatelessWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('المستندات')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        _DocumentCard(icon: Icons.badge_outlined, title: 'إجازة السوق'),
        _DocumentCard(icon: Icons.contact_page_outlined, title: 'الهوية'),
        _DocumentCard(
          icon: Icons.description_outlined,
          title: 'استمارة السيارة',
        ),
        _DocumentCard(
          icon: Icons.directions_car_outlined,
          title: 'صورة السيارة',
        ),
        SizedBox(height: 12),
        Text(
          'رفع المستندات وحالة المراجعة غير متوفرة في خادم جولة حاليًا. '
          'تتم إدارة مستندات السائقين حاليًا عبر إدارة جولة مباشرة.',
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: const Text('غير متوفر في الخادم حاليًا'),
    ),
  );
}
