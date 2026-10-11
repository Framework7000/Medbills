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

  const StoreProfile({
    required this.storeId,
    required this.name,
    this.addressLine = '',
    this.city = '',
    this.state = '',
    this.phone = '',
    this.gstin = '',
    this.drugLicenseNumbers = '',
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
    );
  }
}
