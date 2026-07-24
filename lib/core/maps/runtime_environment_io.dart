import 'dart:io';

bool get isFlutterTestEnvironment =>
    Platform.environment.containsKey('FLUTTER_TEST');
