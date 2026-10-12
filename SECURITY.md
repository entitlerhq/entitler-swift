# Security

Report a vulnerability privately through GitHub's private vulnerability reporting: open the
repository's **Security** tab and choose **Report a vulnerability**. Please do not open a public
issue.

We acknowledge reports within three working days and keep you informed until a fix is released.

The SDK never logs or prints keys, tokens, identity tokens or request and answer bodies, sends
nothing to anyone but the configured base URL, and verifies snapshot signatures only with
CryptoKit or swift-crypto.
