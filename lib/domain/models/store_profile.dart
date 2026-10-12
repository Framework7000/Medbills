import 'date_value.dart';

/// The pharmacy's own details, printed on every tax invoice.
class StoreProfile {
  final String storeId;
  final String name;
  final String addressLine;
  final String city;
  final String state;
  final String phone;
  final String gstin;
  final String drugLicenseNumbers;

  /// Off by default — the owner turns it on in Settings when the store
  /// actually wants to sell on credit. Hidden, not deleted: turning it back
  /// off never touches existing customer/ledger data.
  final bool udhaarEnabled;

  const StoreProfile({
    required this.storeId,
    required this.name,
    this.addressLine = '',
    this.city = '',
    this.state = '',
    this.phone = '',
    this.gstin = '',
    this.drugLicenseNumbers = '',
    this.udhaarEnabled = false,
  });

  String get fullAddress =>
      [addressLine, city, state].where((s) => s.trim().isNotEmpty).join(', ');

  StoreProfile copyWith({
    String? name,
    String? addressLine,
    String? city,
    String? state,
    String? phone,
    String? gstin,
    String? drugLicenseNumbers,
    bool? udhaarEnabled,
  }) {
    return StoreProfile(
      storeId: storeId,
      name: name ?? this.name,
      addressLine: addressLine ?? this.addressLine,
      city: city ?? this.city,
      state: state ?? this.state,
      phone: phone ?? this.phone,
      gstin: gstin ?? this.gstin,
      drugLicenseNumbers: drugLicenseNumbers ?? this.drugLicenseNumbers,
      udhaarEnabled: udhaarEnabled ?? this.udhaarEnabled,
    );
  }

  Map<String, dynamic> toMap() => {
        'storeId': storeId,
        'name': name,
        'addressLine': addressLine,
        'city': city,
        'state': state,
        'phone': phone,
        'gstin': gstin,
        'drugLicenseNumbers': drugLicenseNumbers,
        'udhaarEnabled': udhaarEnabled,
      };

  factory StoreProfile.fromMap(Map<String, dynamic> map) {
    return StoreProfile(
      storeId: readString(map['storeId']),
      name: readString(map['name'], 'MedBills Pharmacy'),
      addressLine: readString(map['addressLine']),
      city: readString(map['city']),
      state: readString(map['state']),
      phone: readString(map['phone']),
      gstin: readString(map['gstin']),
      drugLicenseNumbers: readString(map['drugLicenseNumbers']),
      udhaarEnabled: map['udhaarEnabled'] == true,
    );
  }
}
