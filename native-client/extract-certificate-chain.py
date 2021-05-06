#! /usr/bin/env python3

import re
import subprocess
import sys

# Unpack command line arguments
host = sys.argv[1]
print(f'Downloading certificate chain for {host}')

# Run OpenSSL client to download certificate chain
openssl_result = subprocess.run(
    f'openssl s_client -showcerts -connect {host}:443 < /dev/null',
    encoding='utf-8',
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    shell=True)

# Use regex capturing groups to extract certificates in the chain
regex_pattern_certs = re.compile(r'(-----BEGIN CERTIFICATE-----[\s\S]*?-----END CERTIFICATE-----)+')
for index, match in enumerate(regex_pattern_certs.finditer(openssl_result.stdout)):
    certificate = match.group(1)
    with open(f'{host}.{index}.pem', 'w') as writer:
        writer.write(certificate)
    