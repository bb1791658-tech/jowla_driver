enum IraqiGovernorate {
  anbar('anbar', 'الأنبار'),
  erbil('erbil', 'أربيل'),
  basra('basra', 'البصرة'),
  babylon('babylon', 'بابل'),
  baghdad('baghdad', 'بغداد'),
  halabja('halabja', 'حلبجة'),
  duhok('duhok', 'دهوك'),
  diyala('diyala', 'ديالى'),
  dhiQar('dhi_qar', 'ذي قار'),
  sulaymaniyah('sulaymaniyah', 'السليمانية'),
  salahAlDin('salah_al_din', 'صلاح الدين'),
  qadisiyyah('qadisiyyah', 'الديوانية'),
  karbala('karbala', 'كربلاء'),
  kirkuk('kirkuk', 'كركوك'),
  maysan('maysan', 'ميسان'),
  muthanna('muthanna', 'المثنى'),
  najaf('najaf', 'النجف'),
  nineveh('nineveh', 'نينوى'),
  wasit('wasit', 'واسط');

  const IraqiGovernorate(this.code, this.arabicName);

  final String code;
  final String arabicName;

  static IraqiGovernorate? fromCodeOrName(Object? value) {
    final normalized = _normalize(value?.toString() ?? '');
    if (normalized.isEmpty) return null;
    for (final item in values) {
      if (normalized == _normalize(item.code) ||
          normalized.contains(_normalize(item.arabicName))) {
        return item;
      }
    }
    return null;
  }
}

String _normalize(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[\s_-]+'), '')
    .replaceAll('أ', 'ا')
    .replaceAll('إ', 'ا')
    .replaceAll('آ', 'ا')
    .replaceAll('ى', 'ي');
