# Contributing to KTApple

Thank you for your interest in contributing to KTApple! This document provides guidelines to help you get started.

## Reporting Bugs

If you find a bug, please [open an issue](../../issues/new?template=bug_report.yml) using the bug report template. Include as much detail as possible: steps to reproduce, expected vs actual behavior, your macOS version, and the KTApple version you are running.

## Suggesting Features

Feature ideas are welcome. Please [open a feature request](../../issues/new?template=feature_request.yml) and describe the use case and motivation behind your suggestion.

## Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/m96-chan/KTApple.git
   cd KTApple
   ```
2. Build the project:
   ```bash
   swift build
   ```
3. Run the tests:
   ```bash
   swift test
   ```

Xcode 16 or later is recommended. You can also open the project directly in Xcode via `Package.swift`.

## Pull Request Process

1. **Open an issue first.** Discuss the change you want to make before writing code.
2. **Branch from `main`.** Create a feature or fix branch (e.g. `feature/my-change` or `fix/issue-42`).
3. **Write tests.** Every pull request should include tests that cover the new or changed behavior.
4. **Keep commits focused.** Each commit should represent a single logical change.
5. **Open the PR.** Fill out the pull request template and link the related issue.

A maintainer will review your PR and may request changes. Once approved and CI passes, it will be merged.

## Code Style

- **Swift 6** -- the project targets the Swift 6 language mode. Make sure your code compiles without warnings.
- **Protocol-based abstractions** -- macOS system APIs (Accessibility, window management, etc.) should be accessed through protocol abstractions so they can be substituted in tests.
- **Swift Testing framework** -- use `@Test` and `#expect` from the Swift Testing framework for all new tests.
- Follow the existing code conventions you see in the project. When in doubt, match the surrounding style.

## Code of Conduct

Be respectful and constructive in all interactions. We are committed to providing a welcoming and inclusive experience for everyone.

---

Thanks for helping make KTApple better!
