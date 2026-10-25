# Custom Books Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users add, pick, hide, delete and re-banner books for the dashboard hero comparison, with the hero showing cover-derived banner art and a static, progress-proportional open book.

**Architecture:** A `DashboardBook` value model plus a JSON-backed `DashboardBookStore` feed pure resolution functions in `DashboardProgressBenchmark` (today's Automatic behaviour, generalised). Network access is isolated in small injectable services (Open Library search, Google Books page count, cover cache, banner importer). The hero renders only from local state: beige gradient, `DashboardBookBannerArt`, copy, and a `Canvas`-drawn `DashboardOpenBookView` whose geometry is a pure, unit-tested function.

**Tech Stack:** Swift 5 mode, SwiftUI (`Canvas`), AppKit (`NSImage`, `NSOpenPanel`), ImageIO/CoreImage, `URLSession` (ephemeral), Swift Testing, String Catalog. macOS 15.0 target.

**Spec:** `docs/superpowers/specs/2026-10-25-custom-books-design.md` (read it first; section numbers below, e.g. "§8.6", refer to it).

## Global Constraints

- Platform: macOS deployment target 15.0, Swift 5 language mode; no new dependencies, no API keys, no entitlement changes (sandbox off, `network.client` already on).
- Words per page: `DashboardBookEstimation.wordsPerPage = 275`, defined once. Estimated counts are labelled with "~" everywhere; curated built-in counts have no "~".
- Open Library search: `https://openlibrary.org/search.json?title=<q>&fields=key,title,author_name,first_publish_year,cover_i,number_of_pages_median,edition_count&limit=15`; `URLSession(configuration: .ephemeral)`, `timeoutIntervalForRequest = 10`; `User-Agent: VoiceInk/<CFBundleShortVersionString> (https://tryvoiceink.com)`.
- Search UX: debounce 400 ms, minimum 3 characters, previous search cancelled.
- Cover URL: `https://covers.openlibrary.org/b/id/<id>-L.jpg?default=false`; cache at `~/Library/Caches/com.prakashjoshipax.VoiceInk/BookCovers/<coverID>-L.jpg`; sheet thumbnails use `-S.jpg` via `AsyncImage`, not cached.
- Google Books fallback: only after the user picks a result lacking `number_of_pages_median`; `intitle:` + `inauthor:`; median `pageCount` of results with normalised-equal title and `pageCount >= 40`; behind `static let isGoogleBooksFallbackEnabled = true`; never during type-ahead; all errors swallowed (returns nil).
- Persistence: `~/Library/Application Support/com.prakashjoshipax.VoiceInk/dashboard-books.json`, envelope `{ "version": 1, "books": [...], "builtInArt": {...} }` (version stays 1; new fields optional); writes atomic and off the main thread; corrupt file renamed `.corrupt-<timestamp>.json`, store starts empty. UserDefaults keys: `dashboardSelectedBookID` (String, empty = Automatic) and `dashboardHiddenBuiltInBookIDs` (JSON-encoded `[String]` in a String, via `HiddenBookIDs` `RawRepresentable`).
- Banners: `~/Library/Application Support/com.prakashjoshipax.VoiceInk/BookBanners/<bookID>.jpg` (user data, not cache); http/https only; 10 MB limit (streamed byte count and `Content-Length`); 10 s timeout; downscale to max 1600 px wide; JPEG quality ≈ 0.85; reject width < 300 px; uploads via `NSOpenPanel` limited to `.png`, `.jpeg`, `.heic`.
- Built-in IDs (stable): `builtin.metamorphosis`, `builtin.animal-farm`, `builtin.great-gatsby`, `builtin.iliad`, `builtin.odyssey`, `builtin.iliad-odyssey`, `builtin.war-and-peace`. Custom IDs: `custom.<UUID>`. Built-in titles keep their existing `Localizable.xcstrings` keys (`LocalizedStringResource`); custom titles are never localized.
- Overrides are for custom books only; built-ins are hide/show + optional custom banner only. Duplicate Open Library work keys are blocked ("Already added", disabled).
- Open book is static: no `TimelineView`, no animations, no image assets. Total stack depth `S = 14 pt`; frame 240×118 pt; hairline 0.5 pt only when `0 < P < 0.04` or `0.96 < P < 1`.
- Hero: art on right ~55 % of card; open book and art dropped below ~620 pt card width; open book hidden when locked; locked background keeps `blur(2.5)`, `saturation(0.78)`, white 0.32 overlay.
- Default experience (built-ins, no custom books, no banners) makes zero network requests; no dictation data ever leaves the machine.
- Localization: every new user-facing string ships with de/fr/zh-Hans in the same change (no `new`-state entries).
- Logging: `Logger(subsystem: "com.prakashjoshipax.voiceink", category: …)`.
- Tests: Swift Testing (`import Testing`, `@Test`, `#expect`, `@testable import VoiceInk`) in `Tests/VoiceInkTests/`; the project uses file-system-synchronized groups, so new files need no pbxproj edit. No live-network tests.
- Verification command (every task; replace `<Suite>`; run `make setup` once first if the whisper framework is missing):
  `xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug CODE_SIGN_IDENTITY="" -skipPackagePluginValidation -skipMacroValidation test -only-testing:VoiceInkTests/<Suite>`
  Expected on success: `** TEST SUCCEEDED **`.

## Review Focus

1. **Missing banner/cover file on disk** (`customBannerFile` set but file deleted, or cover never downloaded): hero must fall back to cover, then gradient, never crash or show a spinner. Pinned in Task 2 (`bannerImage` returns nil) and Task 9 (art source fallback).
2. **Garbage manual word counts** ("0", "-5", "12.5", "abc", empty, digit strings overflowing `Int`): rejected, no book created. Pinned in Task 7.
3. **Stale or rapid search results** (typing fast, whitespace-only, <3 chars, unicode/`&`/`#` in titles): an earlier slower response must never overwrite a later query's results; the URL must be correctly escaped. Pinned in Tasks 3 and 7.
4. **Extreme progress** (0 words, a few words of a huge book so `P` ≪ 0.04, a tiny book with `totalPages == 2`, words ≫ book): geometry has no NaN/negative sizes, a non-zero side never disappears, caption stays sensible. Pinned in Task 6.
5. **Hostile or odd image inputs** (HTML at an "image" URL, SVG/PDF bytes, EXIF-rotated JPEG, `Content-Length` lying or absent, redirect to `file:`/`ftp:`, 1×1 image): classified into the six `BannerImportError` cases, never decoded into the store, never crash. Pinned in Task 5.

---

### Task 1: Book model, built-in catalogue, resolution and equivalence

**Files:**
- Create: `VoiceInk/Features/Dashboard/State/DashboardBook.swift`
- Modify: `VoiceInk/Features/Dashboard/State/DashboardStatsModels.swift:420-472` (`DashboardProgressBenchmark`)
- Modify: `VoiceInk/Features/Dashboard/Views/DashboardContent.swift:930-946` (`formattedProgressBenchmarkText`) only enough to compile against the new `equivalence` (Automatic, built-ins only, no store yet)
- Test: `Tests/VoiceInkTests/DashboardBookResolutionTests.swift`, `Tests/VoiceInkTests/DashboardBenchmarkTextTests.swift`, `Tests/VoiceInkTests/BookEstimationTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces (all in module `VoiceInk`):
  - `struct RGB: Codable, Hashable, Sendable { var red, green, blue: Double }`
  - `struct DashboardBook: Codable, Hashable, Identifiable, Sendable` with exactly the §8.1 fields (`id`, `kind`, `title`, `author`, `wordCount`, `wordCountSource`, `estimatedWordCount`, `pageCount`, `openLibraryWorkKey`, `coverID`, `coverTint`, `customBannerFile`, `addedAt`), nested `Kind`, `WordCountSource`, `PageCountProvider`; computed `isEstimate: Bool`, `pagesEquivalent: Int`, `displayTitle: String`.
  - `enum DashboardBookEstimation { static let wordsPerPage: Int; static func words(forPages pages: Int) -> Int }`
  - `DashboardProgressBenchmark.builtInBooks: [DashboardBook]`
  - `struct ResolvedBook: Equatable { let book: DashboardBook; let allowsRepeats: Bool }`
  - `DashboardProgressBenchmark.resolveBook(words: Int, visible: [DashboardBook], selectedID: String?) -> ResolvedBook?`
  - `DashboardProgressBenchmark.isSelectionStale(selectedID: String?, visible: [DashboardBook]) -> Bool`
  - `DashboardProgressBenchmark.progress(words: Int, book: DashboardBook) -> Double` (clamped 0…1)
  - `DashboardProgressBenchmark.Equivalence` now `{ matched(title:), repeated(title:count:), remaining(words:title:isEstimate:), none }`
  - `DashboardProgressBenchmark.equivalence(for words: Int, book: DashboardBook?, allowsRepeats: Bool) -> Equivalence`

- [ ] **Step 1: Write the failing tests**

`BookEstimationTests`:
```swift
@Test func wordsPerPageIs275() { #expect(DashboardBookEstimation.wordsPerPage == 275) }
@Test func estimatedPagesUsePageCount()   // custom, .estimatedFromPages(328, .openLibrary), wordCount 90_200 -> pagesEquivalent == 328
@Test func overrideDerivesPagesFromWords() // .userOverride, wordCount 82_500, pageCount 328 -> pagesEquivalent == 300
@Test func builtInPagesAreWordsOver275()   // builtin.metamorphosis (21_180) -> 77
@Test func pagesEquivalentHasFloorOfTwo()  // wordCount 100, no pageCount -> 2
@Test func isEstimateOnlyForEstimatedSource()
```
`DashboardBookResolutionTests` (visible = `builtInBooks` unless stated):
```swift
@Test func builtInIDsAreUniqueAndStable()  // ids == the seven Global-Constraints IDs, in ascending wordCount order for the six milestones + war-and-peace last
@Test func zeroWordsResolvesFirstBookWithoutRepeats() // 0 -> builtin.metamorphosis, allowsRepeats == false; equivalence == .remaining(words: 21_180, title: <localized>, isEstimate: false)
@Test func betweenMilestonesResolvesLargestPassed() // 25_000 -> metamorphosis; 100_000 -> great-gatsby, allowsRepeats == false, equivalence is .matched (never .repeated)
@Test func atLargestResolvesLargestWithRepeats() // 700_000 -> war-and-peace, allowsRepeats true, .matched; 1_400_000 -> .repeated(count: 2)
@Test func automaticGeneralisesOverVisibleSet() // hide war-and-peace, add custom 900_000-word book: 800_000 -> iliad-odyssey (236_080) matched; 900_000 -> custom, allowsRepeats true
@Test func tiesBreakByID()
@Test func explicitSelectionWinsAndAllowsRepeats() // selectedID builtin.metamorphosis, 100_000 words -> that book, allowsRepeats true, .repeated(count: 4)
@Test func staleSelectionIsDetected() // selectedID not in visible -> isSelectionStale == true; resolveBook falls back to Automatic
@Test func emptyVisibleResolvesNil() // resolveBook == nil; equivalence(for: 5, book: nil, allowsRepeats: false) == .none
@Test func progressIsClamped() // 0 -> 0, 100/600-word book -> 1/6, 2x -> 1.0
```
`DashboardBenchmarkTextTests`: `equivalence` for a custom estimated book returns `.remaining(... isEstimate: true)`; uses `displayTitle` (custom raw title).

- [ ] **Step 2: Run to verify failure**

Run: verification command with `-only-testing:VoiceInkTests/DashboardBookResolutionTests`
Expected: build FAIL, `cannot find 'DashboardBook' in scope`.

- [ ] **Step 3: Implement the model in `DashboardBook.swift`** per §8.1 and the `pagesEquivalent` rule in its notes (`userOverride` → `wordCount / 275`, else `pageCount ?? wordCount/275`, rounded, floor 2). `displayTitle`: built-ins look up a private `[String: LocalizedStringResource]` keyed by ID (keep literal titles so catalog extraction still works); custom returns `title`.

- [ ] **Step 4: Replace `Milestone` lists in `DashboardProgressBenchmark`** with `builtInBooks` (six milestones + War and Peace, `kind: .builtIn`, `.curated`, authors Kafka/Orwell/Fitzgerald/Homer/Homer/Homer/Tolstoy, word counts exactly as today: 21_180, 29_966, 47_094, 114_715, 121_365, 236_080, 700_000).

- [ ] **Step 5: Implement `resolveBook`, `isSelectionStale`, `progress`, `equivalence`** as in §8.4/§8.5. Algorithm not determined by signature: sort `visible` by `(wordCount, id)`; explicit match → `allowsRepeats: true`; otherwise `book = sorted.last { words >= $0.wordCount } ?? sorted.first`, `allowsRepeats = (book == sorted.last)`. `equivalence`: `words < wordCount` → `.remaining`; else if `allowsRepeats && words / wordCount >= 2` → `.repeated(count: words / wordCount)`; else `.matched`.

- [ ] **Step 6: Update `DashboardContent.formattedProgressBenchmarkText`** to call `resolveBook(words:visible: builtInBooks, selectedID: nil)` then `equivalence(...)`, handle `.none` (→ "Dictated %@."), and switch on the new `.remaining(words:title:isEstimate:)` (ignore `isEstimate` for now; Task 9 adds the `~` string). Output for the default list must equal today's.

- [ ] **Step 7: Run tests to verify pass**

Run: verification command for suites `DashboardBookResolutionTests`, `DashboardBenchmarkTextTests`, `BookEstimationTests` (also `AutoLearnAIReviewerTests` as a sibling check).
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add VoiceInk/Features/Dashboard/State/DashboardBook.swift VoiceInk/Features/Dashboard/State/DashboardStatsModels.swift VoiceInk/Features/Dashboard/Views/DashboardContent.swift Tests/VoiceInkTests
git commit -m "feat(dashboard): add DashboardBook model, built-in catalogue and book resolution"
```

---

### Task 2: `DashboardBookStore`, `HiddenBookIDs`, `ImageTint`

**Files:**
- Create: `VoiceInk/Features/Dashboard/State/DashboardBookStore.swift`
- Create: `VoiceInk/Features/Dashboard/State/HiddenBookIDs.swift`
- Create: `VoiceInk/Features/Dashboard/Support/ImageTint.swift`
- Test: `Tests/VoiceInkTests/DashboardBookStoreTests.swift`, `Tests/VoiceInkTests/HiddenBookIDsTests.swift`, `Tests/VoiceInkTests/ImageTintTests.swift`

**Interfaces:**
- Consumes: `DashboardBook`, `RGB`, `DashboardProgressBenchmark.builtInBooks` (Task 1).
- Produces:
  - `struct BuiltInArt: Codable, Equatable { var customBannerFile: String?; var coverTint: RGB? }`
  - `@MainActor final class DashboardBookStore: ObservableObject` with `static let shared`, `init(fileURL: URL, bannersDirectory: URL, fileManager: FileManager = .default)`, `@Published private(set) var customBooks: [DashboardBook]`, `@Published private(set) var builtInArt: [String: BuiltInArt]`, and:
    - `func add(_ book: DashboardBook)`
    - `func update(_ book: DashboardBook)`
    - `func delete(id: String)` (also removes banner file)
    - `func contains(workKey: String) -> Bool`
    - `func setBanner(_ jpegData: Data, forBookID id: String) throws` (writes `<bannersDirectory>/<id>.jpg` atomically, sets `customBannerFile`, recomputes `coverTint` from the banner via `ImageTint`)
    - `func removeBanner(forBookID id: String)`
    - `func setCoverTint(_ tint: RGB?, forBookID id: String)`
    - `func bannerImage(for book: DashboardBook) -> NSImage?` (synchronous; nil if file missing)
    - `func allBooks(hiddenBuiltIns: Set<String>) -> [DashboardBook]` (built-ins merged with `builtInArt`; hidden removed; customs appended)
  - `struct HiddenBookIDs: RawRepresentable, Equatable { var ids: Set<String>; init(ids: Set<String> = []); init?(rawValue: String); var rawValue: String }` (JSON `[String]`, sorted on encode, undecodable → empty set)
  - `enum ImageTint { static func averageColor(of image: NSImage) -> RGB?; static func boardsTint(from color: RGB) -> RGB; static func paletteTint(forBookID id: String) -> RGB }`

- [ ] **Step 1: Write the failing tests**

`DashboardBookStoreTests` (temp directory per test):
```swift
@Test func roundTripsCustomBooks()            // add -> new store on same URL -> customBooks == [book]
@Test func decodesOlderFileWithoutOptionalFields() // JSON with version 1 and a book lacking coverTint/customBannerFile, no builtInArt -> decodes
@Test func corruptFileIsRenamedAndStoreStartsEmpty() // "{not json" -> customBooks.isEmpty, a *.corrupt-*.json sibling exists, original path not overwritten until next save
@Test func deleteRemovesBannerFile()          // setBanner then delete -> file gone
@Test func setBannerWritesFileAndSetsFileName() // customBannerFile == "<id>.jpg"; bannerImage(for:) != nil
@Test func missingBannerFileYieldsNilImage()  // customBannerFile set, file deleted from disk -> bannerImage == nil (no crash)
@Test func removeBannerClearsFieldAndFile()
@Test func builtInBannerLivesInBuiltInArt()   // setBanner for "builtin.iliad" -> builtInArt["builtin.iliad"]?.customBannerFile == "builtin.iliad.jpg"; allBooks merges it onto the built-in
@Test func allBooksHidesHiddenBuiltInsButNeverCustom()
@Test func containsWorkKeyMatchesOnlyCustomBooksWithThatKey()
@Test func envelopeVersionStaysOne()
```
`HiddenBookIDsTests`: round-trip `["builtin.iliad","builtin.odyssey"]`; `HiddenBookIDs(rawValue: "")` → empty; garbage → empty; `rawValue` is sorted JSON (stable).
`ImageTintTests`: solid red 8×8 `NSImage` → `averageColor` ≈ (1,0,0) ±0.02; `boardsTint` darkens each channel ×0.8; `paletteTint` is deterministic for the same ID and returns one of 8 colours.

- [ ] **Step 2: Run to verify failure** — `-only-testing:VoiceInkTests/DashboardBookStoreTests`; expected: `cannot find 'DashboardBookStore'`.

- [ ] **Step 3: Implement `ImageTint`** (`averageColor` via `CIAreaAverage`; `boardsTint` multiplies by 0.8; `paletteTint` indexes a fixed 8-colour cloth palette by a stable hash of the ID — use a hand-rolled FNV-1a, not `hashValue`, which is per-process).

- [ ] **Step 4: Implement `HiddenBookIDs`.**

- [ ] **Step 5: Implement `DashboardBookStore`** following §8.2 and the `DashboardStatsSnapshotStore` pattern (serial `DispatchQueue` for atomic writes, `Logger`). Loads synchronously in `init`. `shared` uses the real Application Support paths from Global Constraints. Decoding failure: rename to `dashboard-books.corrupt-<timestamp>.json`, start empty.

- [ ] **Step 6: Run tests to verify pass** — suites `DashboardBookStoreTests`, `HiddenBookIDsTests`, `ImageTintTests`; expected `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add VoiceInk/Features/Dashboard/State VoiceInk/Features/Dashboard/Support/ImageTint.swift Tests/VoiceInkTests
git commit -m "feat(dashboard): add book store, hidden-ID storage and image tint helper"
```

---

### Task 3: Open Library search and Google Books page-count services

**Files:**
- Create: `VoiceInk/Features/Dashboard/Services/OpenLibraryBookSearchService.swift`
- Create: `VoiceInk/Features/Dashboard/Services/GoogleBooksPageCountService.swift`
- Test: `Tests/VoiceInkTests/OpenLibrarySearchDecodingTests.swift`, `Tests/VoiceInkTests/GoogleBooksPageCountTests.swift`
- Test support: `Tests/VoiceInkTests/Support/StubURLProtocol.swift` (shared by Tasks 3-5)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct BookSearchResult: Identifiable, Hashable, Sendable { let workKey: String; let title: String; let authors: [String]; let firstPublishYear: Int?; let coverID: Int?; let pagesMedian: Int?; var id: String { workKey } }`
  - `enum BookSearchError: Error, Equatable { case offline, timedOut, http(Int), decoding }`
  - `protocol BookSearching: Sendable { func search(title: String) async throws -> [BookSearchResult] }`
  - `struct OpenLibraryBookSearchService: BookSearching { init(session: URLSession = URLSession(configuration: .ephemeral)); static func makeURL(title: String) -> URL?; static func decode(_ data: Data) throws -> [BookSearchResult] }`
  - `protocol PageCountProviding: Sendable { func pageCount(title: String, author: String?) async -> Int? }`
  - `struct GoogleBooksPageCountService: PageCountProviding { static let isGoogleBooksFallbackEnabled: Bool; init(session: URLSession = …); static func medianPageCount(from data: Data, matchingTitle title: String) -> Int? }`
  - `final class StubURLProtocol: URLProtocol` (test-only): `static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?`, `static func makeSession() -> URLSession`

- [ ] **Step 1: Write the failing tests**

```swift
@Test func makeURLEscapesAndPinsFields()  // title "Dune & Messiah #1" -> URL string contains "title=Dune%20%26%20Messiah%20%231", "fields=key,title,author_name,first_publish_year,cover_i,number_of_pages_median,edition_count", "limit=15"
@Test func makeURLTrimsAndRejectsEmpty()  // "  " -> nil
@Test func decodesFixtureWithMissingOptionalFields() // embedded search.json string: one doc has cover_i + pages, one lacks both -> second has coverID nil, pagesMedian nil
@Test func resultsWithNeitherCoverNorPagesSortLast()
@Test func sendsUserAgentHeader()         // stub captures request: User-Agent hasPrefix "VoiceInk/" and contains "tryvoiceink.com"
@Test func mapsOfflineAndTimeout()        // stub throws URLError(.notConnectedToInternet) -> .offline; .timedOut -> .timedOut
@Test func mapsHTTPAndDecodingErrors()    // 503 -> .http(503); body "{}" shaped wrongly -> .decoding
@Test func googleMedianFiltersByTitleAndMinimumPages() // fixture: pageCounts [12, 310, 320, 330] for matching title, one 900 for other title -> 320 (12 < 40 dropped, other title ignored)
@Test func googleReturnsNilOnFailureOr429()
@Test func googleFallbackConstantIsTrue() // #expect(GoogleBooksPageCountService.isGoogleBooksFallbackEnabled)
```

- [ ] **Step 2: Run to verify failure** — `-only-testing:VoiceInkTests/OpenLibrarySearchDecodingTests`; expected: missing symbols.

- [ ] **Step 3: Implement `OpenLibraryBookSearchService`** per §8.3 (`title=` param, `timeoutIntervalForRequest = 10`, User-Agent from `Bundle.main` `CFBundleShortVersionString`, `URLError` → `BookSearchError`, non-2xx → `.http`). Use `URLComponents`/`URLQueryItem` for escaping, but keep `fields` comma-literal in the output.

- [ ] **Step 4: Implement `GoogleBooksPageCountService`** per §7: `q=intitle:<title>+inauthor:<author>&maxResults=5`; normalise titles by case/diacritic/punctuation folding; honour `isGoogleBooksFallbackEnabled` (return nil when false); swallow all errors.

- [ ] **Step 5: Run tests to verify pass** — suites `OpenLibrarySearchDecodingTests`, `GoogleBooksPageCountTests`; expected `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add VoiceInk/Features/Dashboard/Services Tests/VoiceInkTests
git commit -m "feat(dashboard): add Open Library search and Google Books page-count services"
```

---

### Task 4: `BookCoverCache`

**Files:**
- Create: `VoiceInk/Features/Dashboard/Services/BookCoverCache.swift`
- Test: `Tests/VoiceInkTests/BookCoverCacheTests.swift`

**Interfaces:**
- Consumes: `StubURLProtocol` (Task 3).
- Produces: `final class BookCoverCache: @unchecked Sendable { static let shared: BookCoverCache; init(directory: URL, session: URLSession); static func coverURL(for coverID: Int) -> URL; func fileURL(for coverID: Int) -> URL; func cachedImage(for coverID: Int) -> NSImage?; func image(for coverID: Int) async -> NSImage? }`

- [ ] **Step 1: Write the failing tests**

```swift
@Test func coverURLUsesLargeSizeAndDefaultFalse() // == "https://covers.openlibrary.org/b/id/42-L.jpg?default=false"
@Test func fileURLIsCoverIDDashL()                // lastPathComponent == "42-L.jpg"
@Test func imageDownloadsOnceThenServesFromDisk() // stub counts requests: two image(for:) calls -> 1 request; cachedImage(for:) != nil afterwards
@Test func cachedImageIsNilWithoutNetworkOrFile()
@Test func notFoundReturnsNilAndWritesNothing()   // stub 404 -> nil, no file
@Test func corruptDownloadIsNotCached()           // 200 with non-image bytes -> nil, no file
```

- [ ] **Step 2: Run to verify failure** — `-only-testing:VoiceInkTests/BookCoverCacheTests`; expected: missing `BookCoverCache`.

- [ ] **Step 3: Implement `BookCoverCache`** per §8.3 (disk first, `NSCache` in front, 10 s timeout, create the directory on first write, validate bytes decode as image before writing). `shared` uses `~/Library/Caches/com.prakashjoshipax.VoiceInk/BookCovers`.

- [ ] **Step 4: Run tests to verify pass** — suite `BookCoverCacheTests`; expected `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add VoiceInk/Features/Dashboard/Services/BookCoverCache.swift Tests/VoiceInkTests/BookCoverCacheTests.swift
git commit -m "feat(dashboard): add disk-backed Open Library cover cache"
```

---

### Task 5: `BannerImageImporter`

**Files:**
- Create: `VoiceInk/Features/Dashboard/Services/BannerImageImporter.swift`
- Test: `Tests/VoiceInkTests/BannerImageImporterTests.swift`

**Interfaces:**
- Consumes: `StubURLProtocol` (Task 3).
- Produces:
  - `enum BannerImportError: Error, Equatable { case invalidURL, unsupportedScheme, unreachable, timedOut, notAnImage, tooLarge, tooSmall; var userMessage: String }` (messages exactly as the §8.3 table, localized)
  - `protocol BannerImporting: Sendable { func importImage(from url: URL) async throws -> Data; func importImage(fromFile url: URL) throws -> Data }`
  - `struct BannerImageImporter: BannerImporting { static let maxBytes: Int; static let maxPixelWidth: Int; static let minPixelWidth: Int; init(session: URLSession = …) }`

- [ ] **Step 1: Write the failing tests** (fixtures generated in-process with `CGImageDestination`; sizes via a helper `makeImageData(width:height:type:)`):

```swift
@Test func acceptsPNGJPEGAndHEICAndOutputsJPEG()   // output decodes, UTType == .jpeg
@Test func downscalesToMax1600Wide()               // 3200x1000 -> width == 1600
@Test func doesNotUpscaleSmallerImages()           // 800x500 -> width == 800
@Test func appliesEXIFOrientation()                // 600x300 tagged orientation 6 -> output 300x600
@Test func rejectsNonHTTPSchemes()                 // file:, ftp: -> .unsupportedScheme, zero requests made
@Test func rejectsMalformedURL()                   // URL(string:"not a url") path -> .invalidURL
@Test func rejectsHTMLBody()                       // 200 text/html -> .notAnImage
@Test func rejectsSVGAndPDFBytes()                 // -> .notAnImage
@Test func ignoresLyingContentType()               // real PNG served as text/html -> accepted
@Test func rejectsTooSmall()                       // 299 px wide -> .tooSmall; 1x1 -> .tooSmall
@Test func rejectsOversizeByContentLength()        // header 10*1024*1024+1 -> .tooLarge before body read
@Test func rejectsOversizeByStreamedBytesWhenHeaderMissingOrLying()
@Test func mapsNon2xxAndConnectionFailureToUnreachable() // 404, 500, URLError(.cannotFindHost)
@Test func mapsTimeout()                           // URLError(.timedOut) -> .timedOut
@Test func rejectsRedirectToNonHTTP()              // 302 Location: file:///etc/hosts -> .unsupportedScheme or .unreachable (assert not accepted, no file read)
@Test func localFileOver10MBRejectedBeforeDecoding()
@Test func localNonImageFileRejected()
```

- [ ] **Step 2: Run to verify failure** — `-only-testing:VoiceInkTests/BannerImageImporterTests`; expected: missing symbols.

- [ ] **Step 3: Implement `BannerImageImporter`** per §8.3: scheme check before any request; `URLSession(configuration: .ephemeral)` with 10 s request timeout plus an overall 10 s deadline (`withThrowingTaskGroup` race or `Task` + sleep); stream with `bytes(for:)` counting bytes and aborting past `maxBytes`; redirects delegate allows only http/https; decode via `CGImageSource` (never trust `Content-Type`); require a source UTType conforming to `.image` and not PDF/SVG; reject `pixelWidth < 300`; normalise through `CGImageSourceCreateThumbnailAtIndex` (`kCGImageSourceThumbnailMaxPixelSize = 1600`, `kCGImageSourceCreateThumbnailWithTransform = true`) and encode JPEG q ≈ 0.85, flattening alpha onto white.

- [ ] **Step 4: Run tests to verify pass** — suite `BannerImageImporterTests`; expected `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add VoiceInk/Features/Dashboard/Services/BannerImageImporter.swift Tests/VoiceInkTests/BannerImageImporterTests.swift
git commit -m "feat(dashboard): add banner image importer with validation and normalisation"
```

---

### Task 6: `OpenBookGeometry` and `DashboardOpenBookView`

**Files:**
- Create: `VoiceInk/Features/Dashboard/Components/OpenBookGeometry.swift`
- Create: `VoiceInk/Features/Dashboard/Components/DashboardOpenBookView.swift`
- Test: `Tests/VoiceInkTests/OpenBookGeometryTests.swift`

**Interfaces:**
- Consumes: `RGB` (Task 1), `ImageTint.boardsTint` / `paletteTint` (Task 2) by the view only.
- Produces:
  - `struct OpenBookGeometry: Equatable { let progress: Double; let totalPages: Int; let pagesDictated: Int; let isFinished: Bool; let leftDepth: CGFloat; let rightDepth: CGFloat; let leftStackLineCount: Int; let rightStackLineCount: Int; let leftPage: Path; let rightPage: Path; let leftStack: Path; let rightStack: Path; static let totalStackDepth: CGFloat; static let defaultSize: CGSize; static func make(size: CGSize, progress: Double, totalPages: Int) -> OpenBookGeometry }`
  - `enum OpenBookCaption { static func text(pagesDictated: Int, totalPages: Int, ratio: Double, isFinished: Bool) -> String }`
  - `struct DashboardOpenBookView: View { init(progress: Double, ratio: Double, totalPages: Int, title: String, boardsTint: RGB, showsCaption: Bool) }` where `progress` is clamped P, `ratio` is unclamped `words / bookWords` (for the "N×" caption).

- [ ] **Step 1: Write the failing tests**

```swift
@Test func oneSixthProgressGivesOneToFiveStacks() // make(size:default, progress: 100.0/600, totalPages: 600): leftDepth/(leftDepth+rightDepth) within 1/6 ± 0.01; leftDepth ≈ 2.33, rightDepth ≈ 11.67
@Test func zeroProgressHasNoLeftStack()           // leftDepth == 0, rightDepth == 14, pagesDictated == 0
@Test func fullProgressIsFinished()               // progress 1 -> rightDepth == 0, isFinished, pagesDictated == totalPages
@Test func overOneClampsToOne()                   // progress 3.7 -> progress == 1
@Test func negativeAndNaNProgressClampToZero()
@Test func hairlineOnlyNearEdges()                // P 0.02 -> leftDepth >= 0.5; P 0.98 -> rightDepth >= 0.5; P 0.5 -> exact proportional (7.0 / 7.0); P 0.04 and 0.96 -> exact proportional
@Test func tinyBookTwoPagesHasSaneGeometry()      // totalPages 2, progress 0.5 -> pagesDictated 1, no NaN/negative depths, paths non-empty
@Test func tinyProgressOfHugeBookKeepsLeftVisible() // progress 0.0001 -> leftDepth == 0.5 (hairline), pagesDictated == 0
@Test func stackLineCountFollowsDepth()           // max(1, Int(depth / 1.1)) when depth > 0, else 0
@Test func captionVariants()                      // (100, 600, 1/6, false) -> localized "~100 of 600 pages dictated" (en); finished ratio 1.0 -> "All 600 pages dictated"; ratio 2.5 finished -> contains "2" and "×"; (0, 600, 0, false) -> "~0 of 600 pages dictated"
```

- [ ] **Step 2: Run to verify failure** — `-only-testing:VoiceInkTests/OpenBookGeometryTests`; expected: missing `OpenBookGeometry`.

- [ ] **Step 3: Implement `OpenBookGeometry.make`** per §8.7. Pure function: clamp P (NaN → 0), `L = Int((P * Double(T)).rounded())`, `sL = S*P`, `sR = S*(1-P)` with the 0.5 pt hairline only inside `(0, 0.04)` and `(0.96, 1)`, page paths from the quadratic curves given in §8.7, stack paths offset by depth. Use the coordinate frame in §8.7 (gutter at `W/2`, block `y = 14…104`).

- [ ] **Step 4: Implement `OpenBookCaption.text`** with new catalog keys `"~%@ of %@ pages dictated"`, `"All %@ pages dictated"`, `"All %@ pages · %@×"` (numbers via `Formatters.formattedNumber`; `.monospacedDigit()` applied in the view).

- [ ] **Step 5: Implement `DashboardOpenBookView`** as a `Canvas` painter of geometry layers in §8.7 order (boards with 4 pt thickness and 1 pt darker edge and drop shadow `radius 8, y 5, opacity 0.18`; stacks with cream gradient `#F3EAD8 → #E3D6BE` and leaf lines; pages with `#FBF6EC → #EFE5D2`; gutter shadow `black 0.22 → 0` over 18 %; 1 pt crease; deterministic text-hint rows; ribbon bookmark in `DashboardMomentumBackground.accent` when `isFinished`). Static: no `TimelineView`, `.animation(nil, value:)`. Caption below; single accessibility element: label `"Open book: <title>"`, value = caption; drawing `accessibilityHidden(true)`.

- [ ] **Step 6: Run tests to verify pass** — suite `OpenBookGeometryTests`; expected `** TEST SUCCEEDED **`. Then add the temporary SwiftUI `#Preview` states (0 %, 1/6, 50 %, 99 %, 100 %, 250 %) in the view file for eyeball checks in Task 11 (previews stay; they are the repo's norm for visual components — if none exist elsewhere, omit and use Task 11's in-app check).

- [ ] **Step 7: Commit**

```bash
git add VoiceInk/Features/Dashboard/Components/OpenBookGeometry.swift VoiceInk/Features/Dashboard/Components/DashboardOpenBookView.swift Tests/VoiceInkTests/OpenBookGeometryTests.swift
git commit -m "feat(dashboard): add static open-book geometry and Canvas view"
```

---

### Task 7: `BookBannerEditor` and Add Book flow

**Files:**
- Create: `VoiceInk/Features/Dashboard/Views/BookBannerEditor.swift` (contains `BookBannerEditorModel` and `BookBannerEditor` view)
- Create: `VoiceInk/Features/Dashboard/Views/AddBookSheet.swift` (contains `AddBookViewModel` and `AddBookSheet` view)
- Test: `Tests/VoiceInkTests/AddBookViewModelTests.swift`, `Tests/VoiceInkTests/BookBannerEditorModelTests.swift`

**Interfaces:**
- Consumes: `DashboardBook`, `DashboardBookEstimation` (T1); `DashboardBookStore`, `ImageTint` (T2); `BookSearching`, `BookSearchResult`, `BookSearchError`, `PageCountProviding` (T3); `BookCoverCache` (T4); `BannerImporting`, `BannerImportError` (T5).
- Produces:
  - `@MainActor final class BookBannerEditorModel: ObservableObject { init(importer: BannerImporting); @Published private(set) var isWorking: Bool; @Published private(set) var errorMessage: String?; func useURL(_ text: String) async -> Data?; func useFile(_ url: URL) -> Data?; func cancel(); func clearError() }`
  - `struct BookBannerEditor: View { init(model: BookBannerEditorModel, hasCustomBanner: Bool, previewImage: NSImage?, onPrepared: @escaping (Data) -> Void, onRemove: (() -> Void)?) }` (URL field + **Use URL**, **Upload…** via `NSOpenPanel` with `.png/.jpeg/.heic`, **Remove custom banner**, inline error line, disclosure "Downloads the image from the address you enter.")
  - `@MainActor final class AddBookViewModel: ObservableObject` with `init(store: DashboardBookStore, search: BookSearching, pageCounts: PageCountProviding, covers: BookCoverCache, bannerEditor: BookBannerEditorModel, debounce: Duration = .milliseconds(400))`; `@Published var query: String`; `@Published private(set) var state: State`; `enum State: Equatable { case idle, loading, loaded([BookSearchResult]), empty, failed(BookSearchError), needsWordCount(BookSearchResult) }`; `@Published var selected: BookSearchResult?`; `var preparedBannerData: Data?`; `func queryChanged()`; `func retry()`; `func isAlreadyAdded(_ result: BookSearchResult) -> Bool`; `func add() async -> DashboardBook?`; `func submitManualWordCount(_ text: String) async -> DashboardBook?`; `func addManually(title: String, wordCountText: String) -> DashboardBook?`
  - On success `add`/`addManually` writes through `store.add`, applies `preparedBannerData` via `store.setBanner`, and (for books with a `coverID` and no banner) starts a background `covers.image(for:)` then `store.setCoverTint`.

- [ ] **Step 1: Write the failing tests** (stub `BookSearching`/`PageCountProviding`/`BannerImporting` with closures; `debounce: .milliseconds(1)` or `.zero`):

```swift
@Test func belowThreeCharactersNeverSearches()      // "du" -> state .idle, search call count 0; "   " -> idle
@Test func searchTrimsAndFiresAfterDebounce()
@Test func laterQueryWinsOverSlowerEarlierResponse() // search("dune") suspended, search("dune messiah") returns first -> final state shows messiah results; releasing the first does not overwrite
@Test func emptyResultsGiveEmptyState()
@Test func offlineMapsToFailedOffline()
@Test func alreadyAddedWhenWorkKeyMatchesCustomBook() // store has book with openLibraryWorkKey "/works/OL1W" -> isAlreadyAdded true; adding it via add() returns nil and store unchanged
@Test func manualBooksNeverMatchDuplicates()
@Test func addWithPagesCreatesEstimatedBook()       // pagesMedian 328 -> wordCount 90_200 (328*275), source .estimatedFromPages(328, .openLibrary), estimatedWordCount == 90_200
@Test func addWithoutPagesUsesGoogleFallback()      // pagesMedian nil, stub returns 400 -> .estimatedFromPages(400, .googleBooks), wordCount 110_000
@Test func addWithoutPagesAndNoFallbackNeedsWordCount() // stub nil -> state == .needsWordCount, nothing added
@Test func manualWordCountValidation()              // "0", "-5", "12.5", "abc", "", "99999999999999999999999" -> nil, store unchanged; "82500" -> book with .userOverride, wordCount 82_500
@Test func addManuallyRequiresTitleAndCount()       // blank title -> nil; "Notes", "1,000" -> nil (non-integer text); "Notes", "1000" -> .userOverride, no coverID
@Test func preparedBannerIsAppliedOnAdd()           // preparedBannerData set -> store.bannerImage(for:) != nil, customBannerFile non-nil
@Test func cancelledSheetWritesNothing()
```
`BookBannerEditorModelTests`: `useURL` returns data on stub success and nil + `errorMessage == BannerImportError.notAnImage.userMessage` on failure; `useFile` same; error clears on `clearError()`/new input; `cancel()` stops an in-flight `useURL` and clears `isWorking`.

- [ ] **Step 2: Run to verify failure** — `-only-testing:VoiceInkTests/AddBookViewModelTests`; expected: missing `AddBookViewModel`.

- [ ] **Step 3: Implement `BookBannerEditorModel` and `BookBannerEditor`** per §8.4 (Manage Books banner editor). Parsing of the URL text trims whitespace and delegates validation to the importer.

- [ ] **Step 4: Implement `AddBookViewModel`** per §8.3/§8.4: debounced, cancellable search task with a generation counter guarding stale writes; pick-flow word-count logic `pagesMedian ?? (await pageCounts.pageCount(title:author: first author))`; manual-count parsing accepts only `Int` > 0 (`Int(trimmed)`; digits that overflow fail); new custom IDs `"custom.\(UUID().uuidString)"`.

- [ ] **Step 5: Implement `AddBookSheet`** (~460×520; title field; footnote "Searches Open Library over the internet. Only the title you type is sent." plus the Google Books clause when `isGoogleBooksFallbackEnabled`; result rows with `AsyncImage` `-S.jpg` thumbs, author · year, "~84,000 words" or "No page count", disabled "Already added" rows; collapsed "Banner image (optional)" disclosure hosting `BookBannerEditor`; the §8.4 state views; **Add manually…** form; new book becomes selected via a `onAdded: (DashboardBook) -> Void` closure that Task 9 binds to `dashboardSelectedBookID`). Strings use English keys now; translations in Task 10.

- [ ] **Step 6: Run tests to verify pass** — suites `AddBookViewModelTests`, `BookBannerEditorModelTests`; expected `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add VoiceInk/Features/Dashboard/Views/BookBannerEditor.swift VoiceInk/Features/Dashboard/Views/AddBookSheet.swift Tests/VoiceInkTests
git commit -m "feat(dashboard): add Add Book sheet and shared banner editor"
```

---

### Task 8: Manage Books panel

**Files:**
- Create: `VoiceInk/Features/Dashboard/Views/ManageBooksPanel.swift` (contains `ManageBooksViewModel` and `ManageBooksPanel` view)
- Test: `Tests/VoiceInkTests/ManageBooksViewModelTests.swift`

**Interfaces:**
- Consumes: `DashboardBookStore`, `HiddenBookIDs` (T2); `BookBannerEditor`, `BookBannerEditorModel` (T7); `DashboardBook` (T1).
- Produces:
  - `@MainActor final class ManageBooksViewModel: ObservableObject { init(store: DashboardBookStore, hidden: Binding<HiddenBookIDs>, selectedID: Binding<String>); func toggleHidden(_ book: DashboardBook); func delete(_ book: DashboardBook); func saveWordCount(_ text: String, for book: DashboardBook) -> Bool; func resetToEstimate(_ book: DashboardBook); func applyBanner(_ data: Data, to book: DashboardBook) throws; func removeBanner(from book: DashboardBook); func sourceLabel(for book: DashboardBook) -> String }`
  - `struct ManageBooksPanel: View { init(viewModel: ManageBooksViewModel, onAddBook: @escaping () -> Void) }`

- [ ] **Step 1: Write the failing tests**

```swift
@Test func hidingSelectedBuiltInClearsSelection()      // selectedID == "builtin.iliad", toggleHidden -> hidden contains it, selectedID == ""
@Test func hidingUnselectedBuiltInKeepsSelection()
@Test func showingRemovesFromHidden()
@Test func deletingSelectedCustomBookClearsSelectionAndRemovesBanner()
@Test func deleteOnlyAppliesToCustomBooks()            // built-in delete is a no-op
@Test func saveWordCountSetsUserOverrideAndKeepsEstimate() // estimated 90_200 -> save "82500" -> wordCount 82_500, source .userOverride, estimatedWordCount still 90_200
@Test func saveWordCountRejectsGarbage()               // "", "0", "-1", "1.5", "abc" -> false, unchanged
@Test func saveWordCountNotAllowedForBuiltIns()
@Test func resetToEstimateRestoresWordCountAndSource() // back to 90_200, .estimatedFromPages(328, .openLibrary); unavailable when estimatedWordCount == nil
@Test func builtInBannerCanBeSetAndRemoved()           // store.builtInArt updated, allBooks merged value reflects it
@Test func sourceLabels()                              // "estimated from 328 pages", "exact (you entered)", "curated" (localized)
```

- [ ] **Step 2: Run to verify failure** — `-only-testing:VoiceInkTests/ManageBooksViewModelTests`; expected: missing symbols.

- [ ] **Step 3: Implement `ManageBooksViewModel`** per §8.4 (clearing the selection happens in the action itself).

- [ ] **Step 4: Implement `ManageBooksPanel`** for the existing `.sidePanel(isPresented:)` container: sections "Your books" and "Built-in books"; rows with cover/banner thumbnail (`BookCoverCache.cachedImage`/`store.bannerImage`), title/author, word count (with `~` when `isEstimate`) and source label; custom actions **Edit word count…** (popover with integer field, **Save**, **Reset to estimate**), **Banner…** (popover with `BookBannerEditor`), **Delete** (confirmation dialog); built-in actions **Hide/Show** (eye icon) and **Banner…**; footer **Add Book…** calling `onAddBook`.

- [ ] **Step 5: Run tests to verify pass** — suite `ManageBooksViewModelTests`; expected `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add VoiceInk/Features/Dashboard/Views/ManageBooksPanel.swift Tests/VoiceInkTests/ManageBooksViewModelTests.swift
git commit -m "feat(dashboard): add Manage Books panel"
```

---

### Task 9: Hero card, banner art and dashboard wiring

**Files:**
- Create: `VoiceInk/Features/Dashboard/Components/DashboardBookBannerArt.swift` (contains `BookArtSource`, `BannerTreatment`, `DashboardBookBannerArt`)
- Modify: `VoiceInk/Features/Dashboard/Components/DashboardHeroCard.swift` (`DashboardHeroCard`, `DashboardImpactBackground`)
- Modify: `VoiceInk/Features/Dashboard/Views/DashboardContent.swift` (`heroSection` ~l.637, `formattedProgressBenchmarkText`, `.sidePanel` registrations, `@AppStorage`)
- Test: `Tests/VoiceInkTests/BannerSelectionTests.swift`

**Interfaces:**
- Consumes: T1 (`resolveBook`, `equivalence`, `progress`, `isSelectionStale`, `displayTitle`), T2 (`DashboardBookStore`, `HiddenBookIDs`, `ImageTint`), T4 (`BookCoverCache`), T6 (`DashboardOpenBookView`), T7 (`AddBookSheet`, `AddBookViewModel`), T8 (`ManageBooksPanel`, `ManageBooksViewModel`).
- Produces:
  - `struct BookArtSource: Equatable { enum Kind { case customBanner, cover, none }; let kind: Kind; static func resolve(book: DashboardBook, customBannerExists: Bool, coverCached: Bool) -> BookArtSource }`
  - `enum BannerTreatment { static func blurRadius(isCustomBanner: Bool, imagePixelWidth: Int, artWidth: CGFloat, backingScale: CGFloat) -> CGFloat; static let coverBlurRadius: CGFloat; static let lowResCustomBlurRadius: CGFloat; static let artWidthFraction: CGFloat; static let minimumCardWidth: CGFloat }`
  - `struct DashboardBookBannerArt: View { init(image: NSImage, isCustomBanner: Bool) }`
  - `DashboardHeroCard` gains inputs: `book: DashboardBook?`, `progress: Double`, `progressRatio: Double`, `bannerImage: NSImage?`, `isCustomBanner: Bool`, `boardsTint: RGB`, `bookChipImage: NSImage?`, `menuBooks: [DashboardBook]`, `isAutomaticSelected: Bool`, `selectedBookID: String?`, `onSelectAutomatic: () -> Void`, `onSelectBook: (DashboardBook) -> Void`, `onAddBook: () -> Void`, `onManageBooks: () -> Void`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func customBannerBeatsCover()                  // customBannerExists true, coverCached true -> .customBanner
@Test func missingBannerFileFallsBackToCover()       // book.customBannerFile set but customBannerExists false, cover cached -> .cover
@Test func noCoverNoBannerIsNone()                   // -> .none (hero shows gradient + tinted boards)
@Test func removingBannerFallsBackToCover()
@Test func coverAlwaysBlurred()                      // blurRadius(isCustomBanner: false, ...) == BannerTreatment.coverBlurRadius (≈10) for any pixel width
@Test func highResCustomBannerIsSharp()              // pixelWidth 1600, artWidth 400, scale 2 -> 0 (1600 >= 1.5*400*2)
@Test func lowResCustomBannerGetsLightBlur()         // pixelWidth 500 -> lowResCustomBlurRadius (≈4)
@Test func boardsTintFollowsActiveSource()           // helper returns book.coverTint darkened via ImageTint.boardsTint; nil tint -> ImageTint.paletteTint(forBookID:)
```

- [ ] **Step 2: Run to verify failure** — `-only-testing:VoiceInkTests/BannerSelectionTests`; expected: missing `BookArtSource`.

- [ ] **Step 3: Implement `BookArtSource` and `BannerTreatment`** (pure) per §8.6.

- [ ] **Step 4: Implement `DashboardBookBannerArt`**: image `.scaledToFill()` clipped, over-scaled ≈ 1.15× when blurred, horizontal `LinearGradient` mask (clear → opaque by ~40 % of its width), `saturation(0.85)`, warm overlay `Color(red: 1.0, green: 0.86, blue: 0.68)` ≈ 0.20, white veil ≈ 0.10.

- [ ] **Step 5: Rework `DashboardImpactBackground` and `DashboardHeroCard`** per §8.6: keep `Image("momentum-hero-bg")` for books without cover/banner (round-2 ruling, see spec §8.6; beige gradient + art only for books with art); beige `LinearGradient` `(0.98, 0.85, 0.74)` → `(0.99, 0.91, 0.83)` plus soft radial highlight when no art; art frame on the right ~55 %; foreground `HStack` with copy left and `DashboardOpenBookView` right, in front; `ViewThatFits` drops art and book under 620 pt; locked state applies `blur(2.5)`/`saturation(0.78)`/white 0.32 to the background stack and hides the book; book chip in the button row (16×22 cover thumbnail, title ≤ ~180 pt, chevron) opening a `Menu`: **Automatic** (checkmark, no subtitle), divider, visible books ascending by word count (`Title — 21,180 words` / `~90,200 words`, checkmark on selected), divider, **Add Book…**, **Manage Books…**; chip hidden when locked. Author's call from spec: if cluttered, drop the chip thumbnail image only.

- [ ] **Step 6: Wire `DashboardContent`**: `@ObservedObject` `DashboardBookStore.shared`; `@AppStorage("dashboardSelectedBookID") private var selectedBookID = ""`; `@AppStorage("dashboardHiddenBuiltInBookIDs") private var hiddenBooks = HiddenBookIDs()`; compute `visible = store.allBooks(hiddenBuiltIns: hiddenBooks.ids)`, `resolved = resolveBook(...)`, `progress`/`ratio`, `art`/tint; on appear and on change, clear a stale selection (`isSelectionStale`) and start one non-blocking `Task` per session per book to `BookCoverCache.image(for:)` for the selected custom book when it has no custom banner, then `store.setCoverTint` (no retry after failure, silent). `formattedProgressBenchmarkText` gets the estimate variant ("Dictated %@, ~%@ words from %@.") and `.none`. Present `AddBookSheet` via `.sheet` (on add: set `selectedBookID`) and `ManageBooksPanel` via a new `.sidePanel(isPresented:)` alongside the existing four.

- [ ] **Step 7: Run tests to verify pass** — suite `BannerSelectionTests`, then the full unit target (`-only-testing:VoiceInkTests`); expected `** TEST SUCCEEDED **` with no regressions in Tasks 1-8 suites or `AutoLearnAIReviewerTests`. Also run `make build`-equivalent compile: the same command with `build` instead of `test`; expected `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add VoiceInk/Features/Dashboard Tests/VoiceInkTests/BannerSelectionTests.swift
git commit -m "feat(dashboard): cover-derived banner art, open-book hero and book selection wiring"
```

---

### Task 10: Localization, README (asset removal was reversed in round 2: the asset is kept)

**Files:**
- Modify: `VoiceInk/Localizable.xcstrings`
- Modify: `README.md` (under the "Privacy First" bullet, l.34)
- Keep: `VoiceInk/Assets.xcassets/momentum-hero-bg.imageset/` (originally deleted here; restored in round 2 as the default banner)
- Test: `Tests/VoiceInkTests/LocalizationCoverageTests.swift`

**Interfaces:**
- Consumes: all new user-facing strings introduced in Tasks 6-9 (captions, subtitle estimate variant, menu items, sheet/panel copy, disclosures, `BannerImportError.userMessage` texts, accessibility labels, source labels).
- Produces: catalog entries with `en`, `de`, `fr`, `zh-Hans` values in state `translated` for every new key, each with a translator comment; README note.

- [ ] **Step 1: Write the failing test** `LocalizationCoverageTests`: load `Localizable.xcstrings` from the repo (path derived from `#filePath`), take a hard-coded list of the new keys (the exact strings from Tasks 6-9 and the six §8.3 error messages), and `#expect` each exists with non-empty `de`, `fr`, `zh-Hans` localizations whose `state != "new"`; `@Test func catalogHasNoNewStateEntriesForBookKeys()`.

- [ ] **Step 2: Run to verify failure** — `-only-testing:VoiceInkTests/LocalizationCoverageTests`; expected: FAIL listing missing keys.

- [ ] **Step 3: Add the catalog entries** (build once so Xcode extracts keys, then fill translations; comments in the style of existing entries, e.g. "Dashboard book caption. First argument is pages dictated, second is total pages."). Custom book titles are never localized.

- [ ] **Step 4: Update `README.md`**: one short note under "Privacy First": transcription stays fully offline; dashboard book search (Open Library, and Google Books for page counts) and banner-by-URL are opt-in online lookups made only when the user uses them.

- [ ] **Step 5: ~~Delete `momentum-hero-bg.imageset`~~** Reversed in round 2: the imageset stays and is the default banner (`BookArtSource.defaultBanner`); `DashboardImpactBackground` references it.

- [ ] **Step 6: Run tests and build** — suite `LocalizationCoverageTests` then the full `-only-testing:VoiceInkTests`; then the same command with `build`; expected `** TEST SUCCEEDED **` and `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add VoiceInk/Localizable.xcstrings README.md Tests/VoiceInkTests/LocalizationCoverageTests.swift
git add -u VoiceInk/Assets.xcassets
git commit -m "feat(dashboard): localize custom books strings, document opt-in lookups, remove mountain asset"
```

---

### Task 11: Final manual QA

**Files:** none (observation only; fix defects in the owning task's files with a follow-up commit per defect).

**Interfaces:**
- Consumes: the whole feature, running via `make local` or Xcode run of scheme `VoiceInk`.
- Produces: a QA checklist outcome; any defect found becomes a failing test in the owning suite first.

- [ ] **Step 1: Full automated pass** — `xcodebuild ... test -only-testing:VoiceInkTests`; expected `** TEST SUCCEEDED **`.

- [ ] **Step 2: Open-book visual** at 0 %, 1/6, 50 %, 99 %, 100 % and 250 % of the selected book (use a custom book with a small override word count to reach each state). Expect: 100 of 600 pages looks ≈ 1/6 on the left; ≥ 100 % shows no right stack plus the ribbon and "All N pages dictated" / "N×" caption; caption reads "~100 of 600 pages dictated" at 1/6.

- [ ] **Step 3: Banner art** with an Open Library cover (blurred), a high-res custom banner (sharp), a tiny custom banner (light blur), a very light and a very dark cover. Expect headline and subtitle readable at several window widths; fade into the beige is smooth.

- [ ] **Step 4: Fallbacks and layout.** No cover and no banner → beige gradient plus tinted boards. Narrow window (< ~620 pt) → art and book drop, copy untruncated. Locked insights state → blur/desaturation as before, book hidden.

- [ ] **Step 5: Add flow.** Search "Dune" online → pick → added, selected, cover arrives later without a spinner in the hero. Pick an already-added result → "Already added", disabled. Wi-Fi off → "Can't reach Open Library…" with **Add manually…** and **Retry**; add manually with "82500". A result without pages → Google fallback, else the word-count field.

- [ ] **Step 6: Banner import.** Valid image URL; HTML page URL; 404 URL; slow URL (> 10 s); > 10 MB file; PNG, JPEG and HEIC upload; cancel the open panel; **Remove custom banner** returns to the cover; give a built-in a banner and remove it.

- [ ] **Step 7: Selection semantics.** Default books at 0, 25k, 100k, 300k, 700k and 1.5M words → subtitle matches today's output. Hide the selected book → falls back to Automatic with no alert. Hide a built-in that was Automatic's result → next result. Hide all built-ins and delete all custom books → "Dictated X words." and no art, chip shows "Choose a book".

- [ ] **Step 8: Offline default.** With no custom books and no banners, confirm no outbound requests from the dashboard (Little Snitch/`nettop` or Console), including after relaunch.

- [ ] **Step 9: Commit** any fixes made during QA (one commit per fix, each with its regression test); if none, no commit.

---

## Self-Review

**Spec coverage.** §1-4 (intent, goals, anti-goals) → constraints and Tasks 1-9; §5 constraints → Global Constraints; §6 Decisions 1-9 → Tasks 1 (Automatic, built-ins), 3 (search, Google), 7 (add, banner step), 8 (hide/delete/override/banner rows), 9 (hero art, open book in front, locked state), 10 (README, localization); §7 → Task 3 and constant test; §8.1 → T1; §8.2 → T2; §8.3 services → T3/T4/T5; §8.4 flows → T7/T8/T9 (chip + menu), selection resolution → T1/T9; §8.5 text → T1/T9; §8.6 → T9; §8.7 → T6; §8.8 offline/caching → T4/T9/T11; §9 files → covered, plus asset removal and README in T10; §10 tests → each named suite appears in its task (`DashboardBookResolutionTests`, `DashboardBenchmarkTextTests`, `BookEstimationTests`, `OpenBookGeometryTests`, `OpenLibrarySearchDecodingTests`, `DashboardBookStoreTests`, `BannerImageImporterTests`, `BannerSelectionTests`); manual QA → Task 11. §11 open questions are builder choices, not tasks (backup/export is explicitly out of scope).

**Step scan.** Tests give names and assertions with spec values; code steps give signatures and the algorithm only where not determined (resolution, importer pipeline, geometry). No "TBD"/"handle edge cases" steps. One deliberate carve-out: Task 6 Step 6 previews are conditional on repo norms.

**Type consistency.** `DashboardBook.displayTitle`, `ResolvedBook`, `resolveBook`, `equivalence(for:book:allowsRepeats:)` (T1) are used unchanged in T9; `DashboardBookStore.setBanner/removeBanner/bannerImage/setCoverTint/allBooks/contains(workKey:)` (T2) match uses in T7-T9; `BookSearching`/`PageCountProviding`/`BannerImporting` (T3/T5) match T7 inits; `BookBannerEditorModel` (T7) is consumed by T8; `OpenBookGeometry.make` and `OpenBookCaption.text` (T6) match the view init; `HiddenBookIDs.ids` is what T8/T9 bindings use. Fixed during review: `ImageTint` moved into Task 2 so `setBanner` can recompute `coverTint` without a forward dependency; `Equivalence.remaining` gained `isEstimate` in T1 so T9 only adds the string.

**Review Focus.** All five lines have a pinning test: (1) `missingBannerFileYieldsNilImage` (T2) and `missingBannerFileFallsBackToCover` (T9); (2) `manualWordCountValidation`, `saveWordCountRejectsGarbage` (T7/T8); (3) `laterQueryWinsOverSlowerEarlierResponse`, `belowThreeCharactersNeverSearches` (T7) and `makeURLEscapesAndPinsFields` (T3); (4) `tinyBookTwoPagesHasSaneGeometry`, `tinyProgressOfHugeBookKeepsLeftVisible`, `negativeAndNaNProgressClampToZero` (T6); (5) `rejectsHTMLBody`, `rejectsSVGAndPDFBytes`, `appliesEXIFOrientation`, `rejectsOversizeByStreamedBytes…`, `rejectsRedirectToNonHTTP`, `rejectsTooSmall` (T5).

**Proportion.** The plan is shorter than the spec's detail would allow as code; bodies appear nowhere, only signatures, test names and spec values.
