import 'dart:convert';

import 'package:flutter/widgets.dart';

ImageProvider? jowlaImageProvider(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return null;

  if (text.startsWith('data:image/')) {
    final comma = text.indexOf(',');
    if (comma == -1) return null;
    try {
      return MemoryImage(base64Decode(text.substring(comma + 1)));
    } catch (_) {
      return null;
    }
  }

  return NetworkImage(text);
}
