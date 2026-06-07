import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:slip39/slip39dart.dart';

void main() {
  test('SLIP-39 basic split and recovery', () {
    final masterSecret = Uint8List.fromList(List.generate(32, (i) => i)); // 256-bit key
    final groups = [
      [1, 1], // Group 1: 1-of-1
      [2, 3], // Group 2: 2-of-3
    ];
    
    final slip = Slip39.from(
      groups,
      masterSecret: masterSecret,
      passphrase: "test-passphrase",
      threshold: 1, // 1 of the groups is required
    );
    
    expect(slip, isNotNull);
    final mnemonics = slip.mnemonics;
    expect(mnemonics.length, equals(4)); // 1 + 3 = 4
    
    final group1Mnemonic = mnemonics[0];
    final group2Mnemonics = mnemonics.sublist(1);
    
    // Recovery with Group 1
    final recovered1 = Slip39.recoverSecret([group1Mnemonic], passphrase: "test-passphrase");
    expect(recovered1, equals(masterSecret));
    
    // Recovery with Group 2 (any 2 of 3)
    final recovered2 = Slip39.recoverSecret([group2Mnemonics[0], group2Mnemonics[1]], passphrase: "test-passphrase");
    expect(recovered2, equals(masterSecret));
  });
}
