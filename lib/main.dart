import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jowla_driver/app.dart';
import 'package:jowla_driver/core/config/app_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.initialize();
  AppConfig.validateProduction();
  runApp(const ProviderScope(child: JowlaDriverApp()));
}
