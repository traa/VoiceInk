# Custom Books for the Dashboard Benchmark — Design

Date: 2026-10-25 · Status: Draft for implementation · Scope: macOS app `VoiceInk` target only

## 1. Intent and why

The dashboard hero card ("You have saved 1h 9m with VoiceInk" / "Dictated 4,987 words, 16,193 words from The Metamorphosis.") compares the user's lifetime dictated words to a famous book. Today that book is chosen automatically from a short hardcoded list, the user cannot see or change it, and the comparison is shown only as a sentence over a decorative mountain image.

We want the comparison to feel personal and tangible:
- the user picks the book, including any book they own or love, found by title;
- progress is shown as an open book whose left/right page stacks show how far through that book the user's dictation would reach.

## 2. Goals

1. The user adds a book by typing a title, picking a match from Open Library results, and getting its cover and word count automatically. No word-count typing is required.
2. Custom and built-in books appear in one list. Selecting a book drives the hero subtitle, the cover, and the open-book visual.
3. Users can hide built-in books and delete custom books. Hidden or deleted books leave both the selection and the comparison.
4. Users can optionally override a custom book's word count with an exact number. Built-in books are hide/show only (Author's call).
5. The mountain art on the right of the hero is replaced by banner art derived from the selected book's cover (or the user's custom banner), with a natively drawn, static, realistic open book in front of it whose page stacks are proportional to progress, with the caption "~100 of 600 pages dictated".
6. Each book can have a custom banner image (pasted URL or uploaded file) that overrides the cover; it can be removed.
7. Automatic selection keeps today's behaviour (largest book passed, generalised over the visible books).

## 3. Non-goals

- Exact word counts from Project Gutenberg or full-text analysis (possible later improvement).
- Reading tracking, "finished" state, Goodreads-like features, multiple simultaneous books.
- Syncing custom books via iCloud/CloudKit. Including custom books in Settings → Backup export is also a non-goal (see Open questions).
- Changing how dictated words or time saved are computed (`DashboardTimeSaving`, `DashboardStatsSummary.totalWords` stay as they are).
- Animations of the book (page turns, transitions).

## 4. Anti-goals (must never happen)

- Never block the UI or the dashboard render on the network. The hero always renders from local data.
- Never require manual word entry to add a book found by search.
- No API keys, accounts, or paid services.
- Never show an estimated word count as if it were exact. Estimates always carry "~" and an "estimated" label in management UI.
- Never send dictation content, transcripts, or stats anywhere. The only data that leaves the machine is the user-typed search title (Open Library; Google Books for the page-count fallback), cover-ID image requests, and the single user-supplied banner URL the user explicitly submits.
- The default experience (built-in books, no custom books, no banners) makes zero network requests.
- No bundled image assets for the book drawing.

## 5. Constraints found in code

### 5.1 Hero banner
- View: `DashboardHeroCard` in `VoiceInk/Features/Dashboard/Components/DashboardHeroCard.swift`.
  - Inputs: `isLocked`, `headline: DashboardHeroHeadline`, `subtext: String`, the action button props, `reviewCorrectionCount`, and callbacks.
  - Layout: a `VStack` (headline, subtext, then an `HStack` of buttons) with padding 28/18, `minHeight: 160`, clipped to `DashboardLayout.cardCornerRadius` (16).
- Background: `private struct DashboardImpactBackground` draws `Image("momentum-hero-bg")`.
  - The asset is a 2300×597 PNG in `VoiceInk/Assets.xcassets/momentum-hero-bg.imageset/`: a beige→peach full-bleed gradient with low-poly mountains and a sun on the right ~60%.
  - It is drawn `.scaledToFill()`. When locked it gets `blur(2.5)` and `saturation(0.78)` plus a white 0.32 overlay.
  - The "mountain art" is therefore part of a single full-card bitmap, not a separate view.
- Colours: `DashboardMomentumBackground` (`accent`, `headline`, `subtext`).
- Wiring: `DashboardContent.heroSection` in `VoiceInk/Features/Dashboard/Views/DashboardContent.swift` (~l.637). Text comes from:
  - `momentumHeadline` → `.savedTime(formattedAllTimeSaved)`;
  - `momentumSubtext` → `formattedProgressBenchmarkText` (~l.902–946).
- Time saved: `DashboardTimeSaving.timeSaved(words:duration:)` in `VoiceInk/Features/Dashboard/State/DashboardStatsModels.swift` (40 wpm typing estimate minus dictation duration).
- Words: `statsSummary.totalWords`, from `DashboardStatsCache` / `DashboardStatsSnapshotStore` (`VoiceInk/Infrastructure/Persistence/Statistics/DashboardStatsSnapshotStore.swift`, JSON at `~/Library/Application Support/com.prakashjoshipax.VoiceInk/dashboard-stats-snapshot.json`).

### 5.2 Built-in books
They are hardcoded in `enum DashboardProgressBenchmark` (DashboardStatsModels.swift ~l.420–472):
- `private struct Milestone { title: LocalizedStringResource; wordCount: Int }`.
- `repeatBenchmark`: "Tolstoy's War and Peace", 700,000.
- `oneTimeMilestones`:

  | Title | Words |
  |---|---|
  | The Metamorphosis | 21,180 |
  | Animal Farm | 29,966 |
  | The Great Gatsby | 47,094 |
  | Homer's Iliad | 114,715 |
  | Homer's Odyssey | 121,365 |
  | Homer's Iliad and Odyssey | 236,080 |

- `equivalence(for:)` returns `.matched(title)`, `.repeated(title, count)` or `.remaining(words, title)`. It picks the largest milestone already passed. Otherwise it reports the remainder to the first milestone; it never targets the *next* unpassed one after the first is passed. Past 700k it switches to War and Peace multiples.
- No IDs, page counts, authors or covers. Titles are localized (`Localizable.xcstrings` entries commented "Literary benchmark title…").

### 5.3 No existing book menu
- There is **no existing menu or list of books**, and no stored selection. Selection is purely automatic.
- `grep` for `book`, `Milestone`, `benchmark` across `VoiceInk/**/*.swift` finds only `DashboardProgressBenchmark` and its single caller.
- The book list/menu therefore has to be created (see §8.4). This design treats the built-in list as the 7 entries above.

### 5.4 Persistence conventions
- Simple prefs: `@AppStorage` / `UserDefaults.standard` with string keys, e.g. `@AppStorage("dashboardDisplayName")` in `DashboardContent`.
- Small app-owned collections: Codable JSON files in `~/Library/Application Support/com.prakashjoshipax.VoiceInk/`, written by a store. Patterns:
  - `actor AutoLearnReviewProposalStore` (`VoiceInk/Features/Dictionary/AutoLearn/AutoLearnReviewProposalStore.swift`, `auto-learn-review-proposals.json`, `init(fileManager:)`);
  - `DashboardStatsSnapshotStore` (a serial `DispatchQueue` for saves).
- SwiftData (`ModelContainer` in `VoiceInk/App/VoiceInk.swift` `createPersistentContainer`) is used for transcriptions and vocabulary. It is CloudKit-capable (`VoiceInk.entitlements` has iCloud/CloudKit), which makes adding a model costlier (schema migration, CloudKit constraints). Not warranted here.
- No existing `cachesDirectory` usage; no image-cache library. `AsyncImage` is used once (`VoiceInk/App/ChangeLog/Views/ChangeLogView.swift`).

### 5.5 Networking conventions
- There is no shared HTTP client wrapper. Code uses `URLSession` directly with `async`/`await` and checks `HTTPURLResponse.statusCode`:
  - `PolarService` uses `URLSession.shared.data(for:)` with typed `LicenseError`;
  - `CustomModelConnectionTester` and `OpenAICompatibleTranscriptionService` use `URLSession(configuration: .ephemeral)` with `defer { session.finishTasksAndInvalidate() }`;
  - `AnnouncementsService` uses a 10 s timeout and fails silently.
- Logging: `Logger(subsystem: "com.prakashjoshipax.voiceink", category: …)`.

### 5.6 Entitlements and sandbox
- All three entitlement files (`VoiceInk/VoiceInk.entitlements`, `VoiceInk.debug.entitlements`, `VoiceInk.local.entitlements`) have `com.apple.security.app-sandbox = false` and `com.apple.security.network.client = true`.
- No entitlement change is needed.
- Because the app is not sandboxed, `FileManager` Caches/Application Support resolve to the real `~/Library/...` paths.

### 5.7 Privacy statements — RISK (signed off by owner)
- `README.md` l.34: "🔒 **Privacy First**: 100% offline processing ensures your data never leaves your device", plus "privacy-focused" (l.29).
- This feature sends user-typed book titles to Open Library (Internet Archive) and, for the page-count fallback, to Google Books; and it fetches an arbitrary user-pasted image URL for custom banners. Technically the app already goes online (license, announcements, model downloads, cloud transcription), but these are new third-party data flows.
- Owner has signed off the trade-off. Mitigations that remain required:
  - an inline disclosure in the Add Book sheet and under the banner URL field;
  - no network unless the user opens Add Book / the banner editor and acts (the default experience makes zero requests);
  - a README note, now recommended: transcription stays offline; book search and banner-by-URL are opt-in online lookups.
- No CSP or privacy policy file exists in the repo; the external site policy at tryvoiceink.com was not checked.

### 5.8 Build, tests, localization
- Project: `VoiceInk.xcodeproj`, shared scheme `VoiceInk` with testables `VoiceInkTests` and `VoiceInkUITests` (sources in `Tests/VoiceInkTests`, `Tests/VoiceInkUITests`).
- The project uses file-system synchronized groups (`PBXFileSystemSynchronizedRootGroup`), so new `.swift` files under existing folders are picked up without pbxproj edits. Verify for the Tests folder.
- Swift 5 language mode, macOS deployment target 15.0. `Canvas`, `GraphicsContext`, and `MeshGradient` are available (the latter is macOS 15+).
- Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`, `@testable import VoiceInk`). Only one file exists today: `Tests/VoiceInkTests/AutoLearnAIReviewerTests.swift`.
- Build commands:
  - `make build` runs whisper setup first and then `xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug CODE_SIGN_IDENTITY="" -skipPackagePluginValidation -skipMacroValidation build`.
  - For tests, use the same invocation with `test` (optionally `-only-testing:VoiceInkTests`).
- Localization: a single String Catalog `VoiceInk/Localizable.xcstrings`, source `en`, translated into `de`, `fr`, `zh-Hans`.
  - Use `String(localized:)` / `LocalizedStringKey` / `LocalizedStringResource`.
  - Entries carry comments. Interpolations become `%@` keys (e.g. `"Dictated %@, %@ words from %@."`).
  - New user-facing strings must go through the catalog; Xcode extracts them on build. **Author's call:** every new string ships with de/fr/zh-Hans translations in the same change (no `new`-state entries left behind).
  - Custom book titles are user data and are never localized.

## 6. Decisions made (by the product owner)

1. **Add books by search.** The user types a title, the app queries **Open Library** `search.json`, and the user picks a result.
   - Cover comes from `covers.openlibrary.org` by `cover_i`.
   - Word count is **estimated as pages × 275** from `number_of_pages_median`, always labelled as an estimate ("~90,000 words").
2. The user can **override** a **custom** book's word count with an exact number, editable per book. **Author's call:** built-in books cannot be overridden; they are only hidden/shown. This resolves the earlier wording "any book" in favour of custom-only.
3. Custom books appear **in the same list** as built-ins. Selecting a book changes the banner cover/art and the word count used. "Finished" does not matter; the feature only compares dictated words to the book's words.
4. Users can **hide built-in** books; custom books can be **deleted**. Hidden or deleted books are removed from selection and comparison.
5. **Hero art.** The old mountain bitmap is replaced by two things:
   - **Banner art derived from the book's cover** (or the user's custom banner), full-bleed on the right ~55 % of the card, scaled to fill, softly faded into the beige gradient on its left edge, slightly desaturated and warmed so text stays legible; locked state treated as before (§8.6).
   - A **static, natively drawn open book** in front of it, with two spreads, a gutter shadow, page curvature and stacked page edges; left stack ∝ progress (clamped to 0…1), right stack = the remainder; caption "~100 of 600 pages dictated" under the book (the chosen mockup).
   - With no cover and no banner: the beige gradient and the open book with tinted boards.
6. **Project Gutenberg** exact counts are out of scope.
7. **Automatic selection keeps today's behaviour**, generalised over the visible books: the largest book already passed; before any is passed, the remainder to the first book; past the largest, multiples. The open book still shows the resolved book's progress (clamped to 1 when passed). No migration concerns (no existing users).
8. **Privacy signed off.** The Google Books fallback ships (§7); the in-sheet disclosure stays; a README note is recommended (§9).
9. **Custom banners.** Each custom book can have a custom banner image, provided by (a) pasting an http/https image URL (validated by downloading and decoding it, 10 MB limit, 10 s timeout) or (b) an Upload button (`NSOpenPanel`, PNG/JPEG/HEIC). It takes precedence over the Open Library cover. A stored copy (max ~1600 px wide JPEG) lives in Application Support (`BookBanners/<bookID>.jpg`), with a "Remove custom banner" action back to the cover. **Author's call: built-in books can have a custom banner too.** They have no cover at all, so without this they would only ever show the plain gradient, and the control is purely local and opt-in (no default network traffic). The cost is a small `builtInArt` map in the store file because built-ins are not persisted as books. The banner controls live in the Manage Books row and as an optional step in Add Book.

## 7. Google Books fallback — evaluation and recommendation

**What it is.** `GET https://www.googleapis.com/books/v1/volumes?q=intitle:<title>+inauthor:<author>&maxResults=5` works without an API key under a shared, unauthenticated per-IP quota. It returns `volumeInfo.pageCount` for many volumes, including recent/commercial titles where Open Library's `number_of_pages_median` is often missing.

**Downsides:**
- Keyless calls can return 429 under shared quota.
- Results are edition-level and noisy (summaries and study guides have small page counts).
- It adds a second third-party (Google) data flow, which weakens the privacy story.

**Decision (owner signed off): the fallback ships.** It is a narrow, single-shot fallback.
- Call it only after the user *picks* an Open Library result that has no `number_of_pages_median`.
- Send one request with `intitle:` + `inauthor:` (first author) and take the median `pageCount` of results whose normalised title equals the picked title, with `pageCount >= 40`.
- Never call it during type-ahead search.
- On any failure or zero matches, proceed to the manual-entry state (§8.3).
- Disclose it in the same sheet ("Searches Open Library; page counts may come from Google Books").
- Mark `wordCountSource = .estimatedFromPages(pages, provider: .googleBooks)`.
- It sits behind a single `static let isGoogleBooksFallbackEnabled = true` constant (not a user setting) so it can still be removed cleanly later.

## 8. Design

### 8.1 Data model

New file `VoiceInk/Features/Dashboard/State/DashboardBook.swift`:

```swift
struct RGB: Codable, Hashable, Sendable {
    var red: Double    // 0...1
    var green: Double
    var blue: Double
}

struct DashboardBook: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case builtIn, custom }
    enum WordCountSource: Codable, Hashable, Sendable {
        case curated                                   // built-in, hand-checked count
        case estimatedFromPages(pages: Int, provider: PageCountProvider)
        case userOverride                              // exact, typed by user; custom books only
    }
    enum PageCountProvider: String, Codable, Sendable { case openLibrary, googleBooks }

    let id: String            // "builtin.metamorphosis" | "custom.<UUID>"
    let kind: Kind
    var title: String         // custom only; built-ins resolve localized title at read time
    var author: String?
    var wordCount: Int        // effective count used for comparison (> 0)
    var wordCountSource: WordCountSource
    var estimatedWordCount: Int?   // remembered so "Reset to estimate" works after override
    var pageCount: Int?       // from provider; nil for built-ins
    var openLibraryWorkKey: String?  // e.g. "/works/OL45883W"
    var coverID: Int?         // Open Library cover_i
    var coverTint: RGB?       // average colour of the active banner source (custom banner, else cover); nil until computed
    var customBannerFile: String?  // file name in BookBanners/; nil = use the cover (or gradient)
    var addedAt: Date

    var isEstimate: Bool { if case .estimatedFromPages = wordCountSource { true } else { false } }
    var pagesEquivalent: Int { max(2, pageCount ?? Int((Double(wordCount) / 275).rounded())) }
}
```

Notes:
- After a user override, `pagesEquivalent` should be derived from the new word count, not the old `pageCount`. Rule: if `wordCountSource == .userOverride`, use `wordCount / 275`; otherwise use `pageCount` when present.
- Constant: `DashboardBookEstimation.wordsPerPage = 275` (one place, unit-tested).
- `customBannerFile` holds only the file name (`<bookID>.jpg`) inside `BookBanners/`; non-nil means a custom banner exists and takes precedence over the cover. For built-ins the value lives in the envelope's `builtInArt` map and is merged into the built-in `DashboardBook` by `DashboardBookStore.allBooks`.

**Built-in catalogue.** `DashboardProgressBenchmark` is refactored to expose `static let builtInBooks: [DashboardBook]`:
- the 6 one-time milestones plus War and Peace, all `kind: .builtIn`, `wordCountSource: .curated`, `pageCount: nil`;
- stable IDs: `builtin.metamorphosis`, `builtin.animal-farm`, `builtin.great-gatsby`, `builtin.iliad`, `builtin.odyssey`, `builtin.iliad-odyssey`, `builtin.war-and-peace`;
- the localized title stays a `LocalizedStringResource` (keep the existing catalog keys untouched), plus an author (Kafka, Orwell, Fitzgerald, Homer, Homer, Homer, Tolstoy) for the cover drawing.

Built-in counts are shown **without** "~"; they are the existing curated values. Their pages (`words/275`) are always shown with "~".

### 8.2 Persistence

| Data | Where | Why |
|---|---|---|
| Custom books `[DashboardBook]` | `~/Library/Application Support/com.prakashjoshipax.VoiceInk/dashboard-books.json`, versioned envelope `{ "version": 1, "books": [...], "builtInArt": { "<builtinID>": { "customBannerFile": "...", "coverTint": {...} } } }` (version stays 1: `coverTint`, `customBannerFile` and `builtInArt` are all optional, so older files decode unchanged) | Same pattern as `auto-learn-review-proposals.json`; user data, must not be purged. Built-ins are not persisted as books; `builtInArt` holds only their per-user art state (see Decision 9). |
| Selected book | `UserDefaults` key `dashboardSelectedBookID` (`String`, empty = Automatic) via `@AppStorage` | Matches `dashboardDisplayName` |
| Hidden built-ins | `UserDefaults` key `dashboardHiddenBuiltInBookIDs`, a `String` holding a **JSON-encoded `[String]`** (e.g. `["builtin.iliad"]`; empty string = none) | Small pref set; only built-in IDs are stored (custom books are deleted, not hidden). `@AppStorage` has no native `[String]` support. **Author's call:** a small `RawRepresentable` wrapper `HiddenBookIDs: Set<String>` whose `rawValue` is that JSON string, so views use `@AppStorage(key) var hidden = HiddenBookIDs()`; decoding failures yield an empty set. Sorted on encode for stable output. |
| Cover images | `~/Library/Caches/com.prakashjoshipax.VoiceInk/BookCovers/<coverID>-L.jpg` | Re-fetchable cache; purge-safe because the UI falls back to the gradient and a drawn placeholder |
| Custom banners | `~/Library/Application Support/com.prakashjoshipax.VoiceInk/BookBanners/<bookID>.jpg` (downscaled to max ~1600 px wide, JPEG q≈0.85; `<bookID>` is e.g. `custom.<UUID>` or `builtin.iliad`) | **User data, not cache**: the user chose or supplied it and it is not re-fetchable by us, so it lives in Application Support and is never purged. Removed on book delete or "Remove custom banner". |

`DashboardBookStore` (new, `VoiceInk/Features/Dashboard/State/DashboardBookStore.swift`):
- A `@MainActor final class … : ObservableObject` with `@Published private(set) var customBooks`, singleton `shared`, and an `init(fileURL:fileManager:)` for tests.
- It loads synchronously on first access (the file is tiny) and writes atomically (`Data.write(to:options: .atomic)`) off the main thread on a serial queue, mirroring `DashboardStatsSnapshotStore.saveSummary`.
- API: `add(_:)`, `update(_:)` (override/reset), `delete(id:)` (also deletes the book's banner file), `setBanner(_ jpegData: Data, forBookID:)` (writes `BookBanners/<id>.jpg` atomically, sets `customBannerFile`, recomputes `coverTint`), `removeBanner(forBookID:)`, `bannerImage(for:) -> NSImage?` (synchronous, disk-backed, memory-cached keyed by id plus file modification date), and `allBooks(hiddenBuiltIns:) -> [DashboardBook]` (built-ins are merged with their `builtInArt` entry).
- Decoding failure: log, keep the file untouched (rename to `.corrupt-<timestamp>.json`), and start empty.
- **Author's call:** ObservableObject rather than an actor, because the hero reads it synchronously during render.

### 8.3 Services

`OpenLibraryBookSearchService` (new, `VoiceInk/Features/Dashboard/Services/OpenLibraryBookSearchService.swift`):
- Request:

  ```
  https://openlibrary.org/search.json?title=<q>&fields=key,title,author_name,first_publish_year,cover_i,number_of_pages_median,edition_count&limit=15
  ```

  - Use `q=` instead of `title=` if the input contains an author-like "by".
  - **Author's call:** use `title=` primarily, because it ranks better for title input.
- `URLSession(configuration: .ephemeral)` per the existing convention, injected for tests; `timeoutIntervalForRequest = 10`.
- Set `User-Agent: VoiceInk/<CFBundleShortVersionString> (https://tryvoiceink.com)`; Open Library asks clients to identify themselves.
- Returns `[BookSearchResult]` (title, authors, year, coverID, pagesMedian, workKey).
- Ranking: as returned. Results with neither cover nor pages are kept but sorted last.
- Errors: `enum BookSearchError: Error { case offline, timedOut, http(Int), decoding }`, mapped from `URLError.code`.

`GoogleBooksPageCountService` (new, same folder): `func pageCount(title:author:) async -> Int?`. Swallows all errors and returns nil (see §7).

`BookCoverCache` (new):
- `func image(for coverID: Int) async -> NSImage?` checks the disk first, otherwise fetches `https://covers.openlibrary.org/b/id/<id>-L.jpg?default=false` (404 instead of a blank placeholder) and writes it to disk. The large (`-L`) size is used for banner art; thumbnails are downscaled from it.
- `func cachedImage(for:) -> NSImage?` is synchronous and disk-only, for the hero render.
- An in-memory `NSCache` sits in front.
- Cover-ID requests are not rate-limited by Open Library (the 100 per 5 min limit applies to ISBN/OLID lookups). We only use IDs.
- Search-result thumbnails in the sheet use `AsyncImage` with `-S.jpg` (precedent: `ChangeLogView`). They are not cached to disk.

`BannerImageImporter` (new, `VoiceInk/Features/Dashboard/Services/BannerImageImporter.swift`) turns a user-supplied URL or file into normalised banner bytes. It never writes to disk itself; the store does (§8.2).
- API:
  - `func importImage(from url: URL) async throws -> Data` (http/https only);
  - `func importImage(fromFile url: URL) throws -> Data` (NSOpenPanel result);
  - both return JPEG data. Fully injectable `URLSession` for tests.
- Network rules: `URLSession(configuration: .ephemeral)`, `timeoutIntervalForRequest = 10` plus a 10 s overall task deadline, `User-Agent` as in the search service, redirects allowed but only to http/https. Download via `bytes(for:)` so the 10 MB limit is enforced on the *streamed byte count* (abort as soon as it is exceeded), and also pre-checked against `Content-Length` when present.
- Validation: reject schemes other than http/https before any request; require a 2xx status; decode with `CGImageSource` (never trust `Content-Type`); a file that does not decode as an image is rejected. Local files are checked for size (10 MB) before decoding. **Author's call:** reject images narrower than 300 px (`tooSmall`); anything smaller would be an unusably blurry banner.
- Normalisation: decode through `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize = 1600` and `kCGImageSourceCreateThumbnailWithTransform = true` (applies EXIF orientation, downscales without upscaling smaller images), then encode JPEG at quality ≈ 0.85 (`CGImageDestination`). PNG transparency is flattened onto white. HEIC is handled by ImageIO.
- Errors: `enum BannerImportError: Error { case invalidURL, unsupportedScheme, unreachable, timedOut, notAnImage, tooLarge, tooSmall }` with user-facing, localized messages:

  | Error | Message |
  |---|---|
  | `invalidURL` / `unsupportedScheme` | "Enter a web address starting with http:// or https://." |
  | `unreachable` (offline, DNS, TLS, non-2xx) | "Couldn't download that image. Check the address and your connection." |
  | `timedOut` | "The server took too long to respond." |
  | `notAnImage` | "That doesn't look like an image (PNG, JPEG or HEIC)." |
  | `tooLarge` | "That image is larger than 10 MB." |
  | `tooSmall` | "That image is too small to use as a banner (at least 300 px wide)." |

- Privacy: the pasted URL is fetched directly from whatever host the user supplied; this is disclosed under the field ("Downloads the image from the address you enter.").

Word estimate on pick:

```
pages = result.pagesMedian ?? (await googleBooks.pageCount(...))
wordCount = pages.map { $0 * 275 }
```

If `wordCount` is nil, the sheet shows "No page count found" with a required "Word count" field (step 3 of the Add Book flow in §8.4). This is the only time the user types a number, and only because no data exists.

### 8.4 UI flows

**Entry point: book chip in the hero (Author's call).**
- Add a third control to the hero's button row (a wrapping flow, `HeroButtonFlow`, see §8.6.3; at the default width the chip wraps onto a second line): a capsule showing a 16×22 cover thumbnail (dropped if the hero looks cluttered, see §8.6), the book title (truncated, max ~180 pt), and a chevron.
- Clicking it opens a `Menu`:
  - **Automatic** — checkmark when `dashboardSelectedBookID` is empty; no subtitle.
  - Divider. All visible books, sorted by word count ascending, each as `Cover · Title — 21,180 words` or `~90,200 words`; a checkmark marks the selected one.
  - Divider. **Add Book…**, **Manage Books…**
- The chip is hidden while `isLocked` (the insights-locked state already replaces the copy).

**Add Book sheet** (`.sheet`, ~460×520):
1. Text field "Book title". Search fires 400 ms after typing stops, at ≥ 3 characters, and cancels the previous task. A small footnote reads: "Searches Open Library over the internet. Only the title you type is sent." When the Google fallback is on, add "…page counts may come from Google Books."
2. Results list rows: cover thumb (or drawn placeholder), title, author · year, and the right-aligned estimate "~84,000 words" or "No page count". Selecting a row enables **Add**.
3. On **Add**:
   - If the result has pages, the book is created immediately with `.estimatedFromPages`; the sheet closes, the new book becomes **selected**, and the cover downloads in the background.
   - If not, the Google fallback runs (spinner on the button, ≤ 10 s). On a miss, the row expands inline into "We couldn't find a page count. Enter the word count:", with an integer field (> 0) and **Add**.
   - **Duplicate rule (Author's call):** a result whose work key (`key`, e.g. `/works/OL45883W`) matches any existing custom book's `openLibraryWorkKey` is shown with an "Already added" label and is disabled (not selectable, no **Add**). Books added manually have no work key and are never matched. The check is by work key only, not by title.
   - **Optional banner step:** after a result is picked and before **Add**, a collapsed "Banner image (optional)" disclosure shows the same URL and **Upload…** controls as the banner editor. The chosen image is downloaded and validated *immediately* (so errors are shown here, not after **Add**) and held in memory as prepared JPEG data; on **Add** it is written to `BookBanners/<bookID>.jpg` and `customBannerFile` is set. If the user does not touch it, the book uses the cover as its banner. Cancelling the sheet discards the prepared data.
4. States:
   - Empty input: hint.
   - Loading: `ProgressView`.
   - No results: "No books found. Try a shorter title." plus **Add manually…**
   - Offline/timeout: "Can't reach Open Library. Check your connection, or add the book manually." plus **Add manually…** and **Retry**.
   - HTTP/decoding error: generic "Search failed" plus Retry.
5. **Add manually…** takes a title and an exact word count (both required) and produces `.userOverride`, no cover. This is the offline escape hatch; it is never the primary path.

**Manage Books** (side panel via the existing `.sidePanel(isPresented:)` modifier used by `DashboardContent`):
- Two sections, **Your books** and **Built-in books**, each row showing the cover or banner thumbnail, title/author, and the word count with its source label ("estimated from 328 pages", "exact (you entered)", "curated").
- Custom row actions:
  - **Edit word count…** (custom books only) — popover with an integer field and **Save**, which sets `.userOverride` and keeps `estimatedWordCount`. **Reset to estimate** appears when an estimate exists.
  - **Banner…** — opens the shared banner editor popover (see below).
  - **Delete** — confirmation dialog. Also removes the book's banner file.
- Built-in row actions: a **Hide**/**Show** toggle (eye icon) and **Banner…**. Built-ins have no word-count editing and cannot be deleted (Author's call, see Decision 2).
- **Banner editor** (`BookBannerEditor`, shared with the Add Book sheet): a small popover with a thumbnail preview of the current banner source and:
  - a text field "Image URL" (http/https) with a **Use URL** button (spinner while downloading, cancellable);
  - an **Upload…** button that opens an `NSOpenPanel` (`allowedContentTypes: [.png, .jpeg, .heic]`, single selection);
  - **Remove custom banner**, enabled only when a custom banner exists, which deletes the file and returns the book to its cover (or to the gradient if it has none);
  - an inline red error line (see error table in §8.3) that stays until the user changes the input.
- Footer: **Add Book…**

**Selection resolution** (pure function `resolveBook(words:visible:selectedID:)`, unit-tested):

```
visible = builtIns.filter { !hidden.contains($0.id) } + customBooks
sorted  = visible sorted by wordCount ascending (ties by id)
if sorted.isEmpty → nil  (no book: subtitle "Dictated X words.", no book art, no banner art; chip shows "Choose a book")
explicit: sorted.first { $0.id == selectedID }  → that book, allowsRepeats = true
if selectedID is non-empty and not found → clear selectedID (book hidden/deleted) → Automatic
Automatic (today's behaviour, generalised over `sorted`):
    book = sorted.last { words >= $0.wordCount } ?? sorted.first
    allowsRepeats = (book == sorted.last)
```

Notes:
- **Automatic keeps today's behaviour (owner decision):** the largest book already passed is reported as "equivalent to …"; before any book is passed, the remainder to the *first* (smallest) book is reported; at or beyond the largest visible book, multiples of that book are reported ("twice", "N times"). With the default list this is exactly today's output. No migration is needed (no existing users depend on it).
- The open book shows the progress of the resolved book: `P = clamp(words / book.wordCount, 0, 1)`, which is 1 whenever Automatic reports a passed book.
- Clearing on hide/delete happens in the action itself (Manage panel), so stored state never points at a missing book. The render-time check is a defensive fallback.
- Hiding the selected book shows no alert; the chip just shows the Automatic result.
- The "Automatic" menu entry has no subtitle; it is a plain checkmarked row.

### 8.5 Hero subtitle (text)

For the resolved book `b` and dictated words `w`, let `progress = w / b.wordCount`:

| Case | String (new catalog keys, `~` variants for estimates) |
|---|---|
| `w < b.wordCount` | "Dictated %@, %@ words from %@." (existing key), or new "Dictated %@, ~%@ words from %@." when `b.isEstimate` |
| `1 ≤ progress < 2`, or `progress ≥ 2` when repeats are not allowed | "Dictated %@, equivalent to %@." (existing) |
| `progress ≥ 2` and repeats allowed | "Dictated %@, equivalent to %@ %@." (existing; "twice" / "%@ times", where the count is `floor(progress)`) |
| no book | "Dictated %@." (existing) |

- Titles: built-ins use `String(localized: resource)`; custom books use the raw stored title.
- Repeats are allowed for an explicit selection, and for Automatic only when the resolved book is the largest visible book (this reproduces today's War-and-Peace-only multiples).
- Keep `DashboardProgressBenchmark.Equivalence` as the return type. Change `equivalence(for:)` to `equivalence(for words: Int, book: DashboardBook?, allowsRepeats: Bool) -> Equivalence` and add `case none`. `DashboardContent.formattedProgressBenchmarkText` then switches over it exactly as now.

### 8.6 Hero layout and background

Layers, back to front: (1) beige gradient, (2) book banner art on the right, (3) copy on the left and the open book on the right, (4) locked treatment.

1. **Beige gradient.** Remove `Image("momentum-hero-bg")` from `DashboardImpactBackground`. Replace it with a native `LinearGradient` from `Color(red: 0.98, green: 0.85, blue: 0.74)` (top-left) to `Color(red: 0.99, green: 0.91, blue: 0.83)` (right), sampled from the PNG's left side. Delete the `momentum-hero-bg.imageset` asset (clean cutover; it has no other references).
2. **Banner art (`DashboardBookBannerArt`).** The old mountain bitmap is replaced by art derived from the selected book. Source precedence:
   1. the custom banner (`customBannerFile`, §8.2);
   2. the Open Library cover, `-L` size (§8.3);
   3. none: the layer is omitted, leaving the beige gradient with the tinted boards.

   Treatment:
   - Frame: the right ~55 % of the card, full height, full-bleed to the card's top, right and bottom edges (the card already clips to `cardCornerRadius`). The image is `.scaledToFill()` and clipped. A portrait cover is therefore a landscape crop of its middle; that is expected.
   - **Left-edge fade:** a `.mask` with a horizontal `LinearGradient` that is clear at the art's left edge and fully opaque by ~40 % of the art width, so the art dissolves into the beige gradient.
   - **Grading, to keep text contrast and a consistent warm feel:** `saturation(0.85)`, a warm overlay (`Color(red: 1.0, green: 0.86, blue: 0.68)` at ~0.20, `.softLight` or plain overlay) and a faint white veil (~0.10). Numbers are starting points; the builder tunes them.
   - **Low-resolution handling.** Open Library `-M` is only ~180 px wide and even `-L` is ~500 px, scaled to roughly 420 pt × 190 pt (≈ 840 px wide at 2×). Therefore Open Library covers are always drawn with the blurred treatment: `blur(radius ≈ 10)` on the fill image, slightly over-scaled (≈ 1.15×) so blurred edges don't show transparent fringes at the card edges. Fetch the **`-L`** size for banner use (one file, `<coverID>-L.jpg`; the chip/thumbnail is downscaled from it). Custom banners are drawn sharp when `pixelWidth ≥ 1.5 × artWidth × backingScaleFactor`, otherwise with a lighter blur (≈ 4). The sharp cover therefore appears only in the chip thumbnail and in the Manage/Add rows, never magnified into the banner.
   - The art never extends under the copy at normal widths. The copy column keeps its current maximums (`maxWidth: 620` for the subtitle); where they overlap the faded left edge the dark text colours (`DashboardMomentumBackground.headline` / `subtext`) remain legible by construction of the fade and the veil. Builder must verify with a very dark cover and a very light cover.
3. **Foreground.** Card body is an `HStack(alignment: .center)`. The existing copy `VStack` sits on the left (`frame(maxWidth: .infinity, alignment: .leading)`). On the right sits `DashboardOpenBookView` plus a 16 pt caption row, drawn **in front of** the banner art with its own soft drop shadow so cream pages separate from any art. **Author's call:** the book sits in front and the art behind. If the result is cluttered, drop the thumbnail from the hero chip (keep only the title and chevron).
   - **Ruling (Task 9): book scale.** The open book is drawn at 0.8 scale (192×112 pt, not ~240×118; the §8.7 coordinates are design units) so the book and the unsqueezed copy fit the real default card width of ~682 pt (window 950, sidebar 220, 24 pt padding per side). This overrides the earlier "do not shrink" note.
   - **Ruling (Task 9): hero button row.** The hero buttons (insights, review corrections, book chip) sit in a wrapping flow (`HeroButtonFlow`), not a single `HStack`. At the default width the book chip wraps onto a second line, so the card is taller than before.
4. **Narrow widths (Ruling, Task 9):** below ~620 pt the banner art (cover or custom banner) **stays** and only the open book is dropped. A 0.5 beige wash is drawn over the art so the copy stays legible. This is owner-requested (the cover becomes the banner) and overrides the earlier "drops both" behaviour; copy is still never truncated in favour of the book.
5. **Locked state:** the background stack (gradient plus art) gets the same `blur(2.5)`, `saturation(0.78)` and white 0.32 overlay the PNG gets today. When a banner art source exists the art is still drawn, with that treatment applied on top of its own blur logic (the 0.5 beige wash of the no-book layout also applies). **Author's call:** hide the open book and the book chip while locked; the locked prompt needs the space.
6. **Fallback.** No cover and no custom banner (every built-in by default, custom books whose cover is missing or still loading, manually added books): beige gradient plus a soft `RadialGradient` highlight behind the book (white 0.45 → 0), and the open book with tinted boards.
7. **Boards tint.** The hardcover boards under the page blocks use `coverTint` (§8.1): the average colour (`CIAreaAverage`) of the *active banner source* (custom banner if present, else cover), darkened ~20 % so the boards stay distinct from the art behind. It is computed once when that image is first stored or downloaded, persisted, and recomputed when the banner is set or removed. Without a `coverTint`, use a deterministic colour from a hash of `id` over a curated palette of 8 cloth colours (oxblood, navy, forest, ochre, …).

### 8.7 Open-book rendering (static `Canvas`)

New `VoiceInk/Features/Dashboard/Components/DashboardOpenBookView.swift`. Geometry is a pure function, `OpenBookGeometry.make(size:progress:)`, which returns paths and stack counts, so it is unit-testable. The view only paints. No `TimelineView`, no animations, and `.animation(nil)` on value changes.

Inputs:

```
P   = clamp(dictatedWords / book.wordCount, 0, 1)
T   = book.pagesEquivalent                       (≥ 2)
L   = Int((P * Double(T)).rounded())             pages dictated (caption)
```

Caption: "~\(L) of \(T) pages dictated", using a new key "~%@ of %@ pages dictated" with locale-formatted numbers. When P = 1: "All \(T) pages dictated", or "All \(T) pages · %@×" when progress ≥ 2. Use `.monospacedDigit()`, centred under the book, in the fixed `DashboardMomentumBackground.subtext` colour on a white 0.7 capsule (never a semantic colour: the card is light in dark mode too, and the capsule keeps it legible over any banner art).

Coordinate frame (W×H = 240×118, origin top-left):
- Gutter x = W/2.
- Book block from y = 14 to 104. Below it, the boards: a slightly larger rounded rect, 4 pt thick, tinted, with a darker 1 pt edge.

Stack thickness:
- `S = 14 pt` total edge depth to distribute; a constant representing the whole book.
- `sL = S * P`, `sR = S * (1 − P)`.
- This is exactly proportional: 100/600 → sL = 2.33 pt, sR = 11.67 pt, a 1:5 ratio, i.e. visually 1/6 of the total.
- No minimum is applied except a 0.5 pt hairline when 0 < P < 0.04 or 0.96 < P < 1, so a non-zero side never disappears. Document that this is the only distortion.

Stacked page edges:
- Each side's stack is drawn as the pages' outer and bottom edges offset down and outward by up to `sL`/`sR`: the stack grows *below and outside* the top page, like a real book seen from slightly above.
- Fill with a vertical cream gradient (`#F3EAD8` → `#E3D6BE`).
- Overlay `n = max(1, Int(s / 1.1))` thin lines (0.4 pt, `black.opacity(0.08)`) parallel to the outer edge to read as individual leaves.

Page curvature:
- Each top page is a closed path. Its top edge is a quadratic from the outer top corner `(xOuter, 14 + s)` to the gutter `(W/2, 22 + s)` with the control point at `(lerp(xOuter, W/2, 0.55), 6 + s)`. The pages bow up and dip into the spine.
- The bottom edge mirrors this with a smaller sag (gutter y = 100, outer y = 104 − s·0.2).
- The outer edge is a slight convex curve (control point bulging outward 3 pt).
- The page surface is a horizontal `LinearGradient` (paper white `#FBF6EC` at the outer edge → `#EFE5D2` at 85 % toward the gutter).

Gutter shadow:
- A second fill over each page: a `LinearGradient` from `black.opacity(0.22)` at the gutter to 0 over 18 % of the page width.
- Plus a 1 pt dark crease line at x = W/2 drawn on top of both pages.

Text hint:
- On each page, 7–9 rows of 1.2 pt rounded lines (`black.opacity(0.10)`), with lengths from a fixed pseudo-random table so the result is deterministic and static. They follow the page curvature by sampling the top-edge quadratic for y offsets.
- **Author's call:** include it; it sells "realistic" at small sizes.

Drop shadow: `context.addFilter(.shadow(color: .black.opacity(0.18), radius: 8, y: 5))` on the boards layer only.

Progress ≥ 100 %:
- P = 1, so `sR = 0`. The right side is a single page with no stack (the last page; the book is finished).
- Draw a small ribbon bookmark (accent colour `DashboardMomentumBackground.accent`, 5×26 pt with a notched tail) hanging from the gutter top over the right page as the "finished" cue.
- Use the caption variants above. The subtitle already says "equivalent to …" / "… times".

Progress = 0 (no words yet): P = 0 and `sL = 0`, so all pages sit in the right stack. The caption reads "0 of T pages dictated". Before stats load (`hasLoadedStatsSnapshot == false`), draw the book at P = 0 with no caption.

Accessibility: one `accessibilityElement` with label "Open book: <title>" and value "<caption>". Add `accessibilityHidden(true)` for the drawing internals.

Dark mode: the hero is an intentionally light card (fixed colours in `DashboardMomentumBackground`), so book colours are fixed too.

### 8.8 Offline, errors, caching summary

- The hero only reads local state: JSON books, UserDefaults, and disk images via synchronous disk-only lookups (`BookCoverCache.cachedImage(for:)`, `DashboardBookStore.bannerImage(for:)`). A missing image means the beige gradient, the placeholder thumbnail and the palette tint. There is never a spinner in the hero.
- When the dashboard appears, it kicks a low-priority, non-blocking `Task` to fetch a missing cover (`-L`) for the *selected* custom book only, and only if it has no custom banner. It does not retry within the same session after a failure, and it is silent on failure. When the fetch completes it computes `coverTint`, persists it, and the hero re-renders once, with no animation.
- All network work is cancellable (`Task` handles stored in the sheet's state and cancelled on dismiss).
- No HTTP cache configuration is needed (ephemeral sessions). The disk cover cache is the only cache; custom banners are user data, not cache.

## 9. Existing code to touch

| File | Change |
|---|---|
| `VoiceInk/Features/Dashboard/State/DashboardStatsModels.swift` | `DashboardProgressBenchmark`: replace private `Milestone` and the lists with `builtInBooks: [DashboardBook]` (stable IDs). Make `equivalence` take the resolved book and `allowsRepeats`; add `.none`. Add the pure `resolveBook(words:visible:selectedID:)` implementing the generalised current behaviour (§8.4). |
| `VoiceInk/Features/Dashboard/Views/DashboardContent.swift` | Inject `DashboardBookStore`; `@AppStorage` for selection and hidden IDs; feed the resolved book, progress and banner/cover images into `heroSection`; update `formattedProgressBenchmarkText` (estimate variant, `.none`); present the Add Book sheet and Manage Books `.sidePanel`. |
| `VoiceInk/Features/Dashboard/Components/DashboardHeroCard.swift` | New inputs (`book: DashboardBook?`, `progress`, `bannerImage: NSImage?`, `bannerIsCustom`, menu callbacks); `HStack` layout with `DashboardOpenBookView` and a wrapping `HeroButtonFlow` button row; book chip/menu; `DashboardImpactBackground` swaps the bitmap for the beige gradient plus the new `DashboardBookBannerArt` layer (§8.6). |
| `VoiceInk/Assets.xcassets/momentum-hero-bg.imageset/` | Delete. |
| `VoiceInk/Localizable.xcstrings` | New strings (estimate subtitle, caption variants, sheet/panel copy, banner copy and import errors, disclosure, bookmark accessibility), with de/fr/zh-Hans. |
| `README.md` | Recommended (owner signed off the privacy trade-off): add a short note under "Privacy First" that transcription stays fully offline and that dashboard book search and banner-by-URL are opt-in online lookups made only when the user uses them. |

New files:
- `Dashboard/State/DashboardBook.swift`
- `Dashboard/State/DashboardBookStore.swift`
- `Dashboard/Services/OpenLibraryBookSearchService.swift`
- `Dashboard/Services/GoogleBooksPageCountService.swift`
- `Dashboard/Services/BookCoverCache.swift`
- `Dashboard/Services/BannerImageImporter.swift`
- `Dashboard/Components/DashboardOpenBookView.swift` (+ `OpenBookGeometry`)
- `Dashboard/Components/DashboardBookBannerArt.swift`
- `Dashboard/Views/AddBookSheet.swift`
- `Dashboard/Views/ManageBooksPanel.swift`
- `Dashboard/Views/BookBannerEditor.swift` (shared URL/upload/remove control used by both the sheet and the panel)

## 10. Testing approach

Swift Testing in `Tests/VoiceInkTests/` (match `AutoLearnAIReviewerTests.swift` style):
- `DashboardBookResolutionTests`:
  - Automatic with the default books reproduces today's behaviour: 0 words → first book (`remaining`); words between milestones → the largest book already passed (`matched`); at or past the largest book → that book with multiples (700,000 → `matched`, 1,400,000 → `repeated` ×2);
  - Automatic generalised over a visible set that includes a custom book and has some built-ins hidden; ties in word count resolve deterministically (by `id`);
  - Automatic never reports repeats for a non-largest book (100,000 words → Great Gatsby `matched`, not "twice");
  - an explicit selection wins and may report repeats;
  - a hidden or deleted selection falls back to Automatic;
  - all hidden with no custom books → `nil` → `.none`;
  - built-in IDs are unique and stable (snapshot the ID list).
- `DashboardBenchmarkTextTests`: `equivalence(for:book:allowsRepeats:)` covers remaining, matched, repeated (2 → "twice"), and estimate vs exact.
- `BookEstimationTests`:
  - pages × 275;
  - `pagesEquivalent` with a page count, without (words/275 with a floor of 2), and after override.
- `OpenBookGeometryTests`:
  - P = 100/600 gives `sL/(sL+sR) ≈ 1/6` (±0.01);
  - P = 0 → sL = 0;
  - P > 1 clamps to sR = 0 with `isFinished`;
  - the hairline rule applies only in (0, 0.04) and (0.96, 1);
  - caption pages L = round(P·T).
- `OpenLibrarySearchDecodingTests`:
  - decode a recorded `search.json` fixture, embedded as a string, including missing `cover_i` / `number_of_pages_median`;
  - URL construction (escaping, `fields=`, `limit`);
  - error mapping from `URLError.notConnectedToInternet` / `.timedOut` via a `URLProtocol` stub injected through `URLSessionConfiguration.protocolClasses`.
- `DashboardBookStoreTests`: round-trip in a temp directory; corrupt file is renamed and the store starts empty; an older file without `coverTint`, `customBannerFile` or `builtInArt` decodes; delete removes the cover-tint data and the banner file; setting and removing a built-in's banner updates `builtInArt` and the merged `allBooks` output.
- `BannerImageImporterTests` (no live network; `URLProtocol` stub and fixture images generated in-process):
  - accepts PNG, JPEG and a HEIC fixture and always outputs JPEG with width ≤ 1600 and EXIF orientation applied;
  - rejects non-http(s) schemes (`file:`, `ftp:`), malformed URLs, HTML or text bodies (`notAnImage`), an image with width < 300 px (`tooSmall`), a body over 10 MB by `Content-Length` and by streamed byte count when the header is absent or lying (`tooLarge`), 404/5xx (`unreachable`), and a stubbed delay over 10 s (`timedOut`);
  - a local file over 10 MB is rejected before decoding.
- `BannerSelectionTests`: custom banner beats the cover; removing it falls back to the cover; no cover and no banner → gradient-only; the `coverTint` source follows the active banner image.
- No live-network tests.

Manual QA:
- the open-book visual at 0 %, 1/6, 50 %, 99 %, 100 %, and 250 %;
- the banner with: an Open Library cover (blurred treatment), a high-res custom banner, a tiny low-res custom banner, a very light cover, a very dark cover; headline and subtitle stay readable in each at several window widths;
- no cover and no banner → beige gradient plus tinted boards;
- the narrow window (book drops, banner art stays under a beige wash);
- the locked state (blur/desaturation as before, book hidden);
- offline add (Wi-Fi off → error state → Add manually);
- banner import: valid image URL; non-image URL (HTML page); 404 URL; slow URL (> 10 s); > 10 MB file; PNG, JPEG and HEIC upload; cancel the open panel; remove the custom banner → back to cover;
- Automatic: with default books at 0, 25k, 100k, 300k, 700k and 1.5M words the subtitle matches today's behaviour;
- hide the selected book → Automatic; hide a built-in that was Automatic's result → next result;
- hide all and delete all → "Dictated X words." and no art.

Build/test:

```
xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug CODE_SIGN_IDENTITY="" -skipPackagePluginValidation -skipMacroValidation test -only-testing:VoiceInkTests
```

`make build` runs whisper setup first if needed.

## 11. Open questions / left to the builder

1. **Backup/export:** `ImportExportService` (`VoiceInk/Features/Settings/Backup/ImportExportService.swift`) exports settings and vocabulary. Should custom books, banner images and hidden/selection prefs be included? Proposed: a later follow-up, not in this scope.
2. **Auto-fetched covers for built-ins:** built-ins have no cover, so by default they show the beige gradient with tinted boards. Fetching real Open Library covers for built-ins (hardcoded `cover_id`s) would look nicer but adds default network traffic, which the anti-goals forbid. Author's call: no. Users can still give a built-in a custom banner (§8.4, Decision 9).
3. **Built-in page counts:** shown as words/275 ("~77 pages" for The Metamorphosis). Real editions differ; acceptable because it is marked "~".
4. **Builder's choices:** the final banner look (blur radius, desaturation, warm tint, fade width, as long as headline and subtitle stay legible), exact colours, the cloth palette, stack depth `S = 14 pt`, and book size. Keep the proportionality rule and the "only hairline distortion" rule intact.
5. **Open Library `User-Agent`** contact string: confirm the URL or email the owner wants published.
