# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| latest  | :white_check_mark: |

Only the latest release receives security updates.

## Reporting a Vulnerability

If you discover a security vulnerability in RepoPeek, please report it privately rather than opening a public issue.

**Do not open a public issue for security vulnerabilities.**

Please report vulnerabilities by emailing the maintainer at the address listed on the GitHub profile, or use GitHub's [private vulnerability reporting](https://github.com/weirdo-adam/RepoPeek/security/advisories/new) if enabled.

### What to Include

- A clear description of the vulnerability
- Steps to reproduce
- Affected versions
- Any potential impact

### What to Expect

- **Acknowledgment**: You will receive an acknowledgment within 48 hours.
- **Updates**: We will keep you informed of progress toward a fix.
- **Disclosure**: We will coordinate disclosure timing with you and aim to release a fix before public disclosure.

## Security Model

RepoPeek stores GitLab Personal Access Tokens in the **macOS Keychain** for release builds. Debug builds use file-backed storage for development convenience.

- Tokens are never logged or included in network traffic diagnostics.
- Only HTTPS GitLab hosts are supported.
- No credentials are stored in the source repository.

## Scope

The following are in scope:
- Token storage and handling
- Network communication with GitLab APIs
- Local data caching and persistence
- Any code path that processes user credentials

The following are out of scope:
- Vulnerabilities in third-party GitLab instances
- Vulnerabilities in the macOS Keychain itself
- Social engineering attacks
- Physical access attacks
