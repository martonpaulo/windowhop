# Security Policy

## Supported versions

Only the latest release receives fixes.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting
(Security → Report a vulnerability on the repository page), or open a regular issue
if the problem is not sensitive. Reports are usually acknowledged within a week.

## Scope notes

- WindowHop runs with the Accessibility permission, which is powerful: it can read
  window metadata and control windows of other apps. Anything that lets untrusted
  input influence those code paths is in scope.
- Update security: releases are EdDSA-signed and verified by Sparkle before
  installation. Official artifacts are Developer ID signed, notarized, stapled, and
  Gatekeeper-assessed before publication. The private signing and notarization
  credentials are never stored in this repository. Issues with the appcast, signature
  verification, notarization gate, or release workflow are in scope.
- WindowHop performs no network activity other than Sparkle update checks against
  GitHub. Any other observed network traffic is a bug — please report it.
