import 'dart:typed_data';

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

  /// Printed on the invoice.
  final String email;
  final String bankDetails; // bank name, account no., IFSC — several lines
  final String terms; // "Thanks for doing business with us!"
  /// PNG/JPEG pictures for the invoice (kept small: under 150 KB each).
  final Uint8List? logoImage;
  final Uint8List? signatureImage;
  final Uint8List? sealImage;

  static const defaultTerms = 'Thanks for doing business with us! Goods once sold will be taken back only with the bill.';
  static const maxImageBytes = 150 * 1024;

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
    this.email = '',
    this.bankDetails = '',
    this.terms = defaultTerms,
    this.logoImage,
    this.signatureImage,
    this.sealImage,
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
    String? email,
    String? bankDetails,
    String? terms,
    Uint8List? logoImage,
    Uint8List? signatureImage,
    Uint8List? sealImage,
    bool clearLogo = false,
    bool clearSignature = false,
    bool clearSeal = false,
  }) {
    return StoreProfile(
      email: email ?? this.email,
      bankDetails: bankDetails ?? this.bankDetails,
      terms: terms ?? this.terms,
      logoImage: clearLogo ? null : logoImage ?? this.logoImage,
      signatureImage: clearSignature ? null : signatureImage ?? this.signatureImage,
      sealImage: clearSeal ? null : sealImage ?? this.sealImage,
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
        'email': email,
        'bankDetails': bankDetails,
        'terms': terms,
        'logoImage': logoImage,
        'signatureImage': signatureImage,
        'sealImage': sealImage,
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
      email: readString(map['email']),
      bankDetails: readString(map['bankDetails']),
      terms: map['terms'] == null ? defaultTerms : readString(map['terms']),
      logoImage: _bytes(map['logoImage']),
      signatureImage: _bytes(map['signatureImage']),
      sealImage: _bytes(map['sealImage']),
    );
  }
}

Uint8List? _bytes(Object? v) {
  if (v is Uint8List) return v.isEmpty ? null : v;
  if (v is List<int>) return v.isEmpty ? null : Uint8List.fromList(v);
  return null;
}
