import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// A PKCE verifier and the S256 challenge derived from it (RFC 7636).
final class PkcePair {
  const PkcePair({required this.verifier, required this.challenge});

  final String verifier;
  final String challenge;
}

/// base64url without padding, as RFC 7636 section 4.2 requires.
String base64UrlNoPadding(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// The S256 challenge of [verifier]: base64url(SHA-256(verifier)).
String s256Challenge(String verifier) =>
    base64UrlNoPadding(sha256.convert(utf8.encode(verifier)).bytes);

/// A fresh verifier (64 random bytes, 86 base64url chars: inside RFC 7636's
/// 43..128) and its challenge.
PkcePair generatePkcePair({Random? random}) {
  final bytes = List<int>.generate(64, (_) => _nextByte(random));
  final verifier = base64UrlNoPadding(bytes);
  return PkcePair(verifier: verifier, challenge: s256Challenge(verifier));
}

/// The anti-CSRF `state` of one authorization request: 32 random bytes,
/// independent of the verifier.
String generatePkceState({Random? random}) =>
    base64UrlNoPadding(List<int>.generate(32, (_) => _nextByte(random)));

/// `Random.secure()` cannot be seeded; a test that needs a fixed vector passes
/// [random] instead, and the RFC 7636 appendix B vector goes through
/// [s256Challenge] directly.
int _nextByte(Random? random) => (random ?? Random.secure()).nextInt(256);