# Development

Keep this app small: native macOS windows around an offline, read-only document renderer. Prefer a specific fix with a test over a new framework or dependency.

## Code map

| Location | What it does |
| --- | --- |
| `MarkdownReader/AppDelegate.swift`, `MainMenu.swift` | App launch, Open, About, Licenses and Settings |
| `DocumentWindowManager.swift` | Tracks open windows and focuses a document that is already open |
| `MarkdownDocumentWindowController.swift` | One document's loading, history, file watcher and window |
| `MarkdownViewController.swift` | The WebKit view, Find, navigation rules and live reading preferences |
| `DocumentSchemeHandler.swift` | Serves the bundled assets and the current document's images |
| `DocumentFileWatcher.swift` | Notices when the file changes, is replaced or changes permissions |
| `ReadingPreferences.swift`, `ReadingSettingsWindowController.swift` | Saved preferences and the Settings window |
| `ReaderCore/Sources/ReaderCore/` | Markdown-to-HTML rendering, footnotes, and checks on local links and images |
| `ReaderCore/Sources/ReaderCore/Resources/` | Stylesheet, Mermaid runtime and bootstrap, and the Find script |
| `ReaderCore/Tests/`, `Tests/ReaderAppTests/` | Rendering and file-boundary tests; real AppKit/WebKit integration tests |
| `Tests/ToolingTests/`, `scripts/` | Test, privacy-check, attribution and release scripts and their tests |
| `fixtures/visual-review/` | Sample documents for checking rendering by eye |
| `ThirdParty/` | Upstream licenses and notices; keep upstream bytes exact |

`ReaderCore` uses Swift Markdown/cmark 0.8.0, pinned. Mermaid 11.16.1 is a vendored prebuilt file. The Xcode project builds the app; the root `Package.swift` compiles the same sources into a test harness, so a new source file has to be added to both.

## How it works

Opening a file creates a window, then a background operation reads and renders it. A generation counter throws away work that navigation, a reload or closing the window made obsolete. Each window reuses one WKWebView. Every rendered document gets a fresh resource token, so old image and link URLs cannot address a newer document.

A custom URL scheme serves the bundled CSS/JavaScript and validated images. The file watcher coalesces events for 200 ms, and re-attaches when an editor saves by replacing the file. Reading preferences update the page without reloading it. Find runs in an isolated script world and paints matches with the CSS Custom Highlight API, falling back to WebKit's built-in find where that is unavailable. If WebKit's rendering process stops, native controls offer Retry.

## Document boundaries

- Reads regular UTF-8 files up to 20 MiB. Never writes to or deletes source files.
- Raw HTML and MDX are escaped, not evaluated. Code and diagram blocks are limited to 500 KiB, and a document renders at most 100 Mermaid diagrams.
- WebKit uses a nonpersistent data store and a restrictive Content Security Policy. Mermaid renders in sandboxed frames with protected sanitizer settings.
- Local Markdown links must stay in the document's folder or below it. Parent traversal, absolute paths, query strings and symlink escapes are blocked.
- Local images are opened relative to the document's folder without following symlinks. Remote images, SVG and data URLs, control characters and named pipes are rejected.
- Limits: 200 unique images and 200 MiB of image data per document; 25 MiB, 50 megapixels across all frames and 100 frames per image; 500 local links and 1,000 auto-detected links.
- The app is not App-Sandboxed. These checks reduce risk; they are not a guarantee against every hostile file.

## Tests

Run `scripts/test.sh`. It checks the source for private paths and credentials, verifies license attribution, then runs the Python tooling tests, the core Swift tests and the AppKit/WebKit tests. The app tests need a logged-in macOS desktop session and use temporary made-up files.

Set `READER_TEST_ROOT` to choose the cache folder, and `READER_TEST_CONFIGURATION=release` to test an optimized build. A run only counts if Swift Testing prints its final success summary, so an interrupted run cannot pass.

Keep the window tests in the one serialized `ReaderIntegrationTests` suite; its feature files are extensions so they don't compete for NSApplication state. Automated tests don't replace looking at the sample pages, trying keyboard-only and VoiceOver use, and installing a real download.
