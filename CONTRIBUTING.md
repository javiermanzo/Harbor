# Contributing to Harbor

First of all, thank you for your interest in contributing to Harbor! We welcome contributions of all forms—bug reports, feature requests, documentation improvements, and code.

## Development Workflow

1. **Fork the Repository**: Create your own fork of the repository.
2. **Create a Branch**: Create a feature or bugfix branch (`feature/my-feature` or `fix/my-bug`).
3. **Make Changes**: 
   - Ensure you follow the codebase's style (Swift 6 strict concurrency, explicit types).
   - Update tests if you are modifying behavior or adding new features.
   - Run the Example app to verify no UI or compilation warnings exist.
4. **Run Tests**: Execute `swift test` and XCTest in the Example app to ensure everything is passing.
5. **Commit**: Use Conventional Commits (`feat: ...`, `fix: ...`, `docs: ...`, `chore: ...`).
6. **Push and PR**: Push to your fork and submit a Pull Request against the active release branch.

## Setting Up the Project

Simply open `Package.swift` in Xcode or run `swift build` via the command line. 
To run the Example app, open `Example/HarborExample.xcodeproj` in Xcode.

## Code Guidelines

- **Swift 6**: Harbor targets Swift 6. Ensure all your additions compile without warnings under strict concurrency checking. Use `Sendable` where appropriate and properly isolate state with Actors.
- **Documentation**: All public APIs must be documented using DocC-compatible markdown comments (`///`).
- **Testing**: We strive for high test coverage. Any new logic should be accompanied by XCTest cases.

Thank you for contributing!
