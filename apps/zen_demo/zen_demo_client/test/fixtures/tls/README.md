The certificate and private key here are public, disposable localhost test assets.
They identify no real service and must never be used outside the TLS regression
test. The test explicitly trusts the certificate for its own client only; the
default client must reject it, and even a trusting client must reject a mismatched
hostname. No system trust settings are changed.

`ca.crt` is the test CA; its signing key is deliberately absent. The localhost
certificate expires on 2027-10-30. Renew the fixture before then by generating a
new disposable CA and localhost server certificate (RSA 2048+, SHA-256, SAN
`DNS:localhost`, EKU `serverAuth`, leaf validity at most 398 days). Replace all
three files together and run the TLS test. Long-lived leaf certificates are
rejected by Apple even when the issuing test CA is explicitly trusted.
