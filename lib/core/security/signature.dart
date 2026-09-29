import 'dart:convert';

import 'package:crypto/crypto.dart';

class Signature {
  static String compute({required Map<String, String> formData, required String signKey, bool spaceAsPlus = true}) {
    final query = _buildPhpQueryString(formData, spaceAsPlus: spaceAsPlus);

    final hmac = Hmac(sha256, utf8.encode(signKey));
    final hmacDigest = hmac.convert(utf8.encode(query));
    // PHP: md5(hash_hmac('sha256', query, sign_key))
    // hash_hmac returns a HEX string by default, so md5 is applied to that string.
    final md5Digest = md5.convert(utf8.encode(hmacDigest.toString()));

    return md5Digest.toString();
  }

  static String buildPhpQueryString(Map<String, String> formData, {bool spaceAsPlus = true}) {
    return _buildPhpQueryString(formData, spaceAsPlus: spaceAsPlus);
  }

  static String _buildPhpQueryString(Map<String, String> formData, {required bool spaceAsPlus}) {
    final pairs = <String>[];
    for (final entry in formData.entries) {
      final k = entry.key;
      final v = entry.value;
      final ek = _encodePhpComponent(k, spaceAsPlus: spaceAsPlus);
      final ev = _encodePhpComponent(v, spaceAsPlus: spaceAsPlus);
      pairs.add('$ek=$ev');
    }

    return pairs.join('&');
  }

  static String _encodePhpComponent(String input, {required bool spaceAsPlus}) {
    var encoded = Uri.encodeQueryComponent(input);

    if (spaceAsPlus) {
      encoded = encoded.replaceAll('%20', '+');
    } else {
      encoded = encoded.replaceAll('+', '%20');
    }

    encoded = encoded
        .replaceAll('%21', '!')
        .replaceAll('%27', "'")
        .replaceAll('%28', '(')
        .replaceAll('%29', ')')
        .replaceAll('%2A', '*');

    return encoded;
  }
}
