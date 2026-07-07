/// حالة السائق كما في prisma DriverStatus.
enum DriverAccountStatus {
  pendingApproval,
  approved,
  rejected,
  online,
  offline,
  busy,
  onTrip,
  suspended,
}

DriverAccountStatus? driverStatusFromBackend(String? value) {
  return switch (value?.trim().toUpperCase()) {
    'PENDING_APPROVAL' => DriverAccountStatus.pendingApproval,
    'APPROVED' => DriverAccountStatus.approved,
    'REJECTED' => DriverAccountStatus.rejected,
    'ONLINE' => DriverAccountStatus.online,
    'OFFLINE' => DriverAccountStatus.offline,
    'BUSY' => DriverAccountStatus.busy,
    'ON_TRIP' => DriverAccountStatus.onTrip,
    'SUSPENDED' => DriverAccountStatus.suspended,
    _ => null,
  };
}

extension DriverAccountStatusLabel on DriverAccountStatus {
  String get arabicLabel => switch (this) {
        DriverAccountStatus.pendingApproval => 'قيد المراجعة',
        DriverAccountStatus.approved => 'معتمد',
        DriverAccountStatus.rejected => 'مرفوض',
        DriverAccountStatus.online => 'متصل',
        DriverAccountStatus.offline => 'غير متصل',
        DriverAccountStatus.busy => 'مشغول',
        DriverAccountStatus.onTrip => 'في رحلة',
        DriverAccountStatus.suspended => 'موقوف',
      };

  /// حالات يعتبرها Backend متاحة للعمل (socket-auth.service.ts يرفض
  /// PENDING_APPROVAL/REJECTED/SUSPENDED).
  bool get canWork =>
      this != DriverAccountStatus.pendingApproval &&
      this != DriverAccountStatus.rejected &&
      this != DriverAccountStatus.suspended;
}

class DriverProfile {
  const DriverProfile({
    required this.id,
    required this.name,
    required this.phone,
    this.status,
  });

  factory DriverProfile.fromJson(Map<String, dynamic> json) => DriverProfile(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        phone: json['phone']?.toString() ?? '',
        status: driverStatusFromBackend(json['status']?.toString()),
      );

  final String id;
  final String name;
  final String phone;
  final DriverAccountStatus? status;

  String get displayName => name.isEmpty ? phone : name;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        if (status != null) 'status': _statusToBackend(status!),
      };

  DriverProfile copyWith({DriverAccountStatus? status}) => DriverProfile(
        id: id,
        name: name,
        phone: phone,
        status: status ?? this.status,
      );

  static String _statusToBackend(DriverAccountStatus status) =>
      switch (status) {
        DriverAccountStatus.pendingApproval => 'PENDING_APPROVAL',
        DriverAccountStatus.approved => 'APPROVED',
        DriverAccountStatus.rejected => 'REJECTED',
        DriverAccountStatus.online => 'ONLINE',
        DriverAccountStatus.offline => 'OFFLINE',
        DriverAccountStatus.busy => 'BUSY',
        DriverAccountStatus.onTrip => 'ON_TRIP',
        DriverAccountStatus.suspended => 'SUSPENDED',
      };
}

class DriverSession {
  const DriverSession({
    required this.accessToken,
    required this.refreshToken,
    required this.driver,
  });

  final String accessToken;
  final String refreshToken;
  final DriverProfile driver;
}

class OtpRequestResult {
  const OtpRequestResult({
    required this.requestId,
    this.expiresAt,
    this.mockCode,
  });

  factory OtpRequestResult.fromJson(Map<String, dynamic> json) =>
      OtpRequestResult(
        requestId: json['requestId']?.toString() ?? '',
        expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? ''),
        mockCode: json['mockCode']?.toString(),
      );

  final String requestId;
  final DateTime? expiresAt;
  final String? mockCode;
}
