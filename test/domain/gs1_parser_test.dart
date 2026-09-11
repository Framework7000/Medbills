import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/domain/services/gs1_parser.dart';

void main() {
  group('Gs1Parser', () {
    test('parses plain EAN-13', () {
      final result = Gs1Parser.parse('8901234567890');
      expect(result.gtin, '8901234567890');
      expect(result.batchNumber, isNull);
    });

    test('parses parenthesized GS1 string', () {
      final result = Gs1Parser.parse('(01)08901234567890(17)261200(10)BATCH123');
      expect(result.gtin, '08901234567890');
      expect(result.batchNumber, 'BATCH123');
      expect(result.expiryDate, DateTime(2026, 12, 31));
    });

    test('applies DD=00 rule: last day of the month', () {
      final result = Gs1Parser.parse('(17)260200');
      expect(result.expiryDate, DateTime(2026, 2, 28));
    });

    test('parses unparenthesized GS1 string', () {
      final result = Gs1Parser.parse('01089012345678901726120010BATCH123');
      expect(result.gtin, '08901234567890');
      expect(result.expiryDate, DateTime(2026, 12, 31));
      expect(result.batchNumber, 'BATCH123');
    });
  });
}
