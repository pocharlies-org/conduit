/// Comprehensive input validation service
class InputValidationService {
  /// Validate URL (enhanced version for server addresses)
  static String? validateUrl(String? value, {bool required = true}) {
    if (value == null || value.isEmpty) {
      return required ? 'Server address is required' : null;
    }

    final trimmed = value.trim();

    // Add protocol if missing
    String urlToValidate = trimmed;
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      urlToValidate = 'http://$trimmed';
    }

    try {
      final uri = Uri.parse(urlToValidate);

      // Validate scheme
      if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
        return 'Use http:// or https:// only';
      }

      // Validate host
      if (!uri.hasAuthority || uri.host.isEmpty) {
        return 'Please enter a server address (e.g., 192.168.1.10:3000)';
      }

      // Validate port if specified
      if (uri.hasPort) {
        if (uri.port < 1 || uri.port > 65535) {
          return 'Port must be between 1 and 65535';
        }
      }

      // Validate IP address format if it looks like an IP
      if (_isIPAddress(uri.host) && !_isValidIPAddress(uri.host)) {
        return 'Invalid IP address format (use 192.168.1.10)';
      }
    } catch (e) {
      return 'Invalid server address format';
    }

    return null;
  }

  /// Check if a string looks like an IP address
  static bool _isIPAddress(String host) {
    return RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(host);
  }

  /// Validate IP address format
  static bool _isValidIPAddress(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;

    for (final part in parts) {
      final num = int.tryParse(part);
      if (num == null || num < 0 || num > 255) return false;
    }
    return true;
  }

  /// Validate required field
  static String? validateRequired(
    String? value, {
    String fieldName = 'This field',
  }) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  /// Composite validator that runs multiple validators
  static String? Function(String?) combine(
    List<String? Function(String?)> validators,
  ) {
    return (String? value) {
      for (final validator in validators) {
        final result = validator(value);
        if (result != null) {
          return result;
        }
      }
      return null;
    };
  }
}
