import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../errors/app_exception.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> pushAppRoute(String location) async {
  final context = rootNavigatorKey.currentContext;
  if (context == null) {
    throw const AppException('تعذر فتح الشاشة المطلوبة حالياً. حاول مجدداً.');
  }
  await GoRouter.of(context).push<void>(location);
}
