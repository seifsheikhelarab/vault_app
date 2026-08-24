import 'package:flutter_test/flutter_test.dart';
import 'package:vault_app/core/money/money.dart';

void main() {
  group('parsePiasters', () {
    test('zero in every legal spelling', () {
      expect(parsePiasters('0'), 0);
      expect(parsePiasters('0.0'), 0);
      expect(parsePiasters('0.00'), 0);
      expect(parsePiasters('00'), 0);
    });

    test('leading zeros preserved as value, not text', () {
      expect(parsePiasters('007'), 700);
      expect(parsePiasters('007.5'), 750);
      expect(parsePiasters('007.05'), 705);
      expect(parsePiasters('000.99'), 99);
    });

    test('whole pounds and one-decimal inputs', () {
      expect(parsePiasters('10'), 1000);
      expect(parsePiasters('10.5'), 1050);
      expect(parsePiasters('123456789'), 12345678900);
    });

    test('two decimals exact', () {
      expect(parsePiasters('10.55'), 1055);
      expect(parsePiasters('0.01'), 1);
      expect(parsePiasters('0.99'), 99);
    });

    test('surrounding whitespace tolerated', () {
      expect(parsePiasters(' 12.34 '), 1234);
    });

    test('rejects more than two decimals', () {
      expect(() => parsePiasters('1.234'), throwsFormatException);
      expect(() => parsePiasters('1.23456789'), throwsFormatException);
    });

    test('rejects empty and whitespace-only', () {
      expect(() => parsePiasters(''), throwsFormatException);
      expect(() => parsePiasters('   '), throwsFormatException);
    });

    test('rejects garbage and structural junk', () {
      for (final bad in [
        '.',
        '.5',
        '5.',
        '-3',
        '-3.20',
        '1,000',
        '12a',
        'abc',
        '1..2',
        '1.2.3',
        '+5',
        '١٢', // Arabic-Indic digits
      ]) {
        expect(() => parsePiasters(bad), throwsFormatException,
            reason: 'should reject "$bad"');
      }
    });
  });

  group('formatPiasters', () {
    test('always two decimals', () {
      expect(formatPiasters(0), '0.00');
      expect(formatPiasters(1), '0.01');
      expect(formatPiasters(50), '0.50');
      expect(formatPiasters(1050), '10.50');
      expect(formatPiasters(1055), '10.55');
      expect(formatPiasters(12345), '123.45');
      expect(formatPiasters(12345678900), '123456789.00');
    });

    test('rejects negatives', () {
      expect(() => formatPiasters(-1), throwsArgumentError);
    });
  });

  group('round trip', () {
    test('parse(format(p)) == p exactly', () {
      const samples = [0, 1, 9, 10, 99, 100, 101, 999, 1000, 12345, 99999999];
      for (final p in samples) {
        expect(parsePiasters(formatPiasters(p)), p, reason: 'p=$p');
      }
    });

    test('format(parse(s)) canonicalizes without value change', () {
      expect(formatPiasters(parsePiasters('007.5')), '7.50');
      expect(formatPiasters(parsePiasters('0')), '0.00');
    });

    test('every piaster value in a dense range survives the loop', () {
      for (var p = 0; p <= 2000; p++) {
        expect(parsePiasters(formatPiasters(p)), p);
      }
    });
  });

  group('formatEgp', () {
    test('prefixes EGP', () {
      expect(formatEgp(125000), 'EGP 1250.00');
      expect(formatEgp(0), 'EGP 0.00');
    });
  });
}
