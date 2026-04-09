import 'dart:convert';
import 'package:cryptography/cryptography.dart';

void main() async {
  final pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 10000,
    bits: 256,
  );
  
  final secretKey = await pbkdf2.deriveKey(
    secretKey: SecretKey(utf8.encode("my_password")),
    nonce: utf8.encode("user@example.com"),
  );
  
  final bytes = await secretKey.extractBytes();
  print(base64Encode(bytes));
}
