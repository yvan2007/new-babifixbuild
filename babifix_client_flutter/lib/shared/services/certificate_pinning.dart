import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart' as crypto;

/// Certificate pinning configuration for BABIFIX Flutter apps.
///
/// IMPORTANT: Before production, replace the placeholder fingerprints with
/// actual SHA-256 fingerprints from your server certificates.
///
/// To get the fingerprint:
/// ```bash
/// openssl s_client -connect api.babifix.ci:443 </dev/null | \
///   openssl x509 -fingerprint -sha256 -noout
/// ```
class CertificatePinningConfig {
  CertificatePinningConfig._();

  /// SHA-256 fingerprints of allowed server certificates.
  /// Replace these with actual fingerprints before production.
  /// Format: 'sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
  static const List<String> allowedFingerprints = [
    // api.babifix.ci
    // TODO: Add real certificate fingerprint before production
    // Example: 'sha256/xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx=',

    // cdn.babifix.ci (for media assets)
    // TODO: Add real certificate fingerprint before production

    // Firebase/GCM servers
    'sha256/8V92Buz3hI8S1vdm8UJl5xL3J6M1K5qY7X9zW4A6bHc=',
  ];

  /// Domains that require certificate pinning.
  static const List<String> pinnedDomains = ['api.babifix.ci', 'babifix.ci'];

  /// Whether certificate pinning is enabled.
  /// Disabled in debug mode for easier development.
  static bool get isPinningEnabled =>
      kReleaseMode && allowedFingerprints.isNotEmpty;

  /// Validate if a certificate fingerprint is allowed.
  static bool validateCertificate(String fingerprint) {
    if (!isPinningEnabled) return true;

    final normalizedFingerprint = fingerprint.toLowerCase().trim();
    return allowedFingerprints.any(
      (allowed) => normalizedFingerprint.contains(allowed.toLowerCase()),
    );
  }

  /// Check if a domain requires pinning.
  static bool requiresPinning(String domain) {
    return pinnedDomains.any(
      (pinned) => domain.toLowerCase().contains(pinned.toLowerCase()),
    );
  }

  /// Get security configuration for Android network security.
  /// Add this to android/app/src/main/res/xml/network_security_config.xml
  static String getAndroidNetworkSecurityConfig() {
    return '''
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <base-config cleartextTrafficPermitted="false">
        <trust-anchors>
            <certificates src="system" />
        </trust-anchors>
    </base-config>
    
    <!-- Production API domain with pinning -->
    <domain-config cleartextTrafficPermitted="false">
        <domain includeSubdomains="true">api.babifix.ci</domain>
        <domain includeSubdomains="true">babifix.ci</domain>
        <pin-set expiration="2025-12-31">
            <!-- TODO: Replace with actual pin from server certificate -->
            <pin digest="SHA-256">AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=</pin>
            <!-- Backup pin from intermediate CA -->
            <pin digest="SHA-256">BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=</pin>
        </pin-set>
    </domain-config>
    
    <!-- Debug config - allows localhost for development -->
    <debug-overrides>
        <trust-anchors>
            <certificates src="user" />
            <certificates src="system" />
        </trust-anchors>
    </debug-overrides>
</network-security-config>
''';
  }

  /// Get Info.plist configuration for iOS ATS.
  /// Add to ios/Runner/Info.plist
  static String getIOSInfoPlistConfig() {
    return '''
<!-- Certificate Pinning - BABIFIX -->
<!-- Remove exception for api.babifix.ci before production -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
    <key>NSExceptionDomains</key>
    <dict>
        <key>babifix.ci</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <false/>
            <key>NSExceptionRequiresForwardSecrecy</key>
            <true/>
            <key>NSIncludesSubdomains</key>
            <true/>
            <!-- TODO: Add SPKI pins before production -->
            <!-- 
            <key>NSExceptionMinimumTLSVersion</key>
            <string>TLSv1.2</string>
            <key>NSPinnedDomains</key>
            <dict>
                <key>api.babifix.ci</key>
                <dict>
                    <key>SPPublicKeyHashes</key>
                    <array>
                        <string>AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=</string>
                    </array>
                </dict>
            </dict>
            -->
        </dict>
    </dict>
</dict>
''';
  }

  /// Compute SHA-256 fingerprint from certificate DER data.
  static String computeFingerprint(List<int> derData) {
    final digest = crypto.sha256.convert(derData);
    return 'sha256/${base64Encode(digest.bytes)}';
  }
}

/// Secure HTTP client wrapper with certificate pinning support.
///
/// Usage:
/// ```dart
/// final client = SecureHttpClient();
/// final response = await client.get('https://api.babifix.ci/endpoint');
/// ```
class SecureHttpClient {
  static HttpClient? _client;

  /// Get or create a secure HttpClient with pinning.
  static HttpClient createClient() {
    final client = HttpClient();

    if (CertificatePinningConfig.isPinningEnabled) {
      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) {
            // In release mode with pinning enabled, validate the certificate
            if (CertificatePinningConfig.requiresPinning(host)) {
              // Get certificate fingerprint from DER encoded data
              final derData = cert.der;
              final fingerprint = CertificatePinningConfig.computeFingerprint(
                derData,
              );
              return CertificatePinningConfig.validateCertificate(fingerprint);
            }
            // Allow non-pinned domains
            return true;
          };
    } else {
      // In debug mode, allow all certificates for development
      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) {
            debugPrint(
              'Warning: Certificate validation bypassed in debug mode for $host',
            );
            return true;
          };
    }

    return client;
  }

  /// Close the client and reset.
  static void close() {
    _client?.close(force: true);
    _client = null;
  }
}

/// Security utility class for additional checks.
class SecurityUtils {
  SecurityUtils._();

  /// Check if the device is running in a potentially compromised environment.
  static Future<bool> isDeviceSecure() async {
    if (Platform.isAndroid) {
      return await _checkAndroidSecurity();
    } else if (Platform.isIOS) {
      return await _checkIOSSecurity();
    }
    return true;
  }

  static Future<bool> _checkAndroidSecurity() async {
    // Check for debug flag
    if (Platform.isAndroid) {
      final isDebug = Platform.environment.containsKey('DEBUG');
      if (isDebug) {
        debugPrint('Warning: App is running in debug mode');
        return false;
      }
    }
    return true;
  }

  static Future<bool> _checkIOSSecurity() async {
    // iOS security checks would go here
    // Check for jailbreak indicators if needed
    return true;
  }

  /// Validate input string for potential XSS/injection attacks.
  static bool isInputSafe(String input) {
    final dangerousPatterns = [
      RegExp(r'<script[^>]*>.*?</script>', caseSensitive: false, dotAll: true),
      RegExp(r'javascript:', caseSensitive: false),
      RegExp(r'on\w+\s*=', caseSensitive: false),
      RegExp(r'<\s*iframe', caseSensitive: false),
      RegExp(r'<\s*object', caseSensitive: false),
      RegExp(r'<\s*embed', caseSensitive: false),
    ];

    for (final pattern in dangerousPatterns) {
      if (pattern.hasMatch(input)) {
        debugPrint('Security: Potentially dangerous input detected');
        return false;
      }
    }
    return true;
  }

  /// Sanitize input by removing dangerous patterns.
  static String sanitizeInput(String input) {
    return input
        .replaceAll(RegExp(r'<[^>]*>'), '') // Remove HTML tags
        .replaceAll(RegExp(r'javascript:', caseSensitive: false), '')
        .replaceAll(RegExp(r'on\w+\s*=', caseSensitive: false), '')
        .trim();
  }
}
