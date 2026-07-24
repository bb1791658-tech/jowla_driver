import 'package:flutter/material.dart';

enum CallMethod { devicePhone, jowla }

Future<CallMethod?> showCallMethodSheet(
  BuildContext context, {
  required bool phoneAvailable,
}) {
  return showModalBottomSheet<CallMethod>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            title: Text(
              'اختر طريقة الاتصال',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          ListTile(
            enabled: phoneAvailable,
            leading: const Icon(Icons.phone_outlined),
            title: const Text('اتصال عبر هاتف الجهاز'),
            subtitle: Text(
              phoneAvailable
                  ? 'استخدام تطبيق الهاتف الافتراضي'
                  : 'رقم الهاتف غير متاح لهذه الرحلة',
            ),
            onTap: phoneAvailable
                ? () => Navigator.pop(context, CallMethod.devicePhone)
                : null,
          ),
          ListTile(
            leading: const Icon(Icons.call_rounded),
            title: const Text('اتصال عبر جولة'),
            subtitle: const Text('مكالمة صوتية داخل التطبيق'),
            onTap: () => Navigator.pop(context, CallMethod.jowla),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
