"""
Utility script to fetch and compute SSL certificate SHA-256 fingerprint.
Run this when your production server is live:

    python generate_ssl_fingerprint.py api.babifix.ci 443

Output can be pasted into certificate_pinning.dart
"""
import ssl
import base64
import sys
import socket
import hashlib


def get_certificate_fingerprint(host: str, port: int = 443) -> str:
    """Fetch server certificate and compute SHA-256 fingerprint."""
    context = ssl.create_default_context()
    with socket.create_connection((host, port), timeout=10) as sock:
        with context.wrap_socket(sock, server_hostname=host) as ssock:
            der_cert = ssock.getpeercert(binary_form=True)
            sha256_hash = hashlib.sha256(der_cert).digest()
            fingerprint_b64 = base64.b64encode(sha256_hash).decode('ascii')
            return f'sha256/{fingerprint_b64}'


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: python generate_ssl_fingerprint.py <domain> [port]')
        print('Example: python generate_ssl_fingerprint.py api.babifix.ci 443')
        sys.exit(1)

    domain = sys.argv[1]
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 443

    print(f'Fetching certificate from {domain}:{port}...')
    try:
        fingerprint = get_certificate_fingerprint(domain, port)
        print(f'\nSHA-256 Fingerprint: {fingerprint}')
        print(f'\nPaste this into certificate_pinning.dart as:')
        print(f"  'sha256/{fingerprint.split(\"/\")[1]}',")
    except Exception as e:
        print(f'Error: {e}')
        sys.exit(1)
