import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/domain/services/amount_words.dart';

void main() {
  test('amounts in words, Indian style', () {
    expect(rupeesInWords(0), 'Zero Rupees only');
    expect(rupeesInWords(100), 'One Rupee only');
    expect(rupeesInWords(6700), 'Sixty Seven Rupees only');
    expect(rupeesInWords(123450), 'One Thousand Two Hundred Thirty Four Rupees and Fifty Paise only');
    expect(rupeesInWords(1250000 * 100), 'Twelve Lakh Fifty Thousand Rupees only');
    expect(rupeesInWords(1000000005), 'One Crore Rupees and Five Paise only');
    expect(rupeesInWords(21011100), 'Two Lakh Ten Thousand One Hundred Eleven Rupees only');
  });
}
