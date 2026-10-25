# Custom Books for the Dashboard Benchmark — Design

Date: 2026-10-25 · Status: Draft for implementation · Scope: macOS app `VoiceInk` target only

## 1. Intent and why

The dashboard hero card ("You have saved 1h 9m with VoiceInk" / "Dictated 4,987 words, 16,193 words from The Metamorphosis.") compares the user's lifetime dictated words to a famous book. Today that book is chosen automatically from a short hardcoded list, the user cannot see or change it, and the comparison is shown only as a sentence over a decorative mountain image.

We want the comparison to feel personal and tangible:
- the user picks the book, including any book they own or love, found by title;
- progress is shown as a grid colour reveal over the banner art: the art is divided into cells (one per page, at most 240); cells already dictated show the art in full colour, the rest show it muted.

## 2. Goals

1. The user adds a book by typing a title, picking a match from Open Library results, and getting its cover and word count automatically. No word-count typing is required.
2. Custom and built-in books appear in one list. Selecting a book drives the hero subtitle, the cover, and the grid reveal.
3. Users can hide built-in books and delete custom books. Hidden or deleted books leave both the selection and the comparison.
4. Users can optionally override a custom book's word count with an exact number. Built-in books are hide/show only (Author's call).
5. Books that have a cover or a custom banner get banner art derived from it on the right of the hero (replacing the mountain art for those books; books with neither keep the original mountain bitmap, §8.6), revealed as a grid: one cell per page (at most 240), dictated cells in full colour and the rest muted, with the caption "~100 of 600 pages dictated" on a small dark pill (§8.7).
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
5. **Hero art.** For books with a cover or custom banner the old mountain bitmap is replaced by two things (books with neither keep the bitmap, §8.6):
   - **Banner art derived from the book's cover** (or the user's custom banner), full-bleed on the right ~55 % of the card, scaled to fill, softly faded into the beige gradient on its left edge, slightly desaturated and warmed so text stays legible; locked state treated as before (§8.6).
   - A **grid colour reveal** over that art (§8.7): `min(totalPages, 240)` cells; dictated cells show the art in full colour, the others muted; a small dark caption pill "~100 of 600 pages dictated" sits in the art's lower-right corner. (Round 3 replaced the earlier static open-book illustration.)
   - With no cover and no banner: the original mountains bitmap is the art, with the same grid reveal.
6. **Project Gutenberg** exact counts are out of scope.
7. **Automatic selection keeps today's behaviour**, generalised over the visible books: the largest book already passed; before any is passed, the remainder to the first book; past the largest, multiples. The grid reveal still shows the resolved book's progress (clamped to 1 when passed). No migration concerns (no existing users).
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
- Add a third control to the hero's button row (the wrapping flow `HeroButtonFlow`; with the copy no longer sharing the card with an illustration it fits on one line at the default ~682 pt card width): a capsule showing a 16×22 cover thumbnail, the book title (truncated, max ~180 pt), and a chevron.
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
- The grid reveal shows the progress of the resolved book: `p = clamp(words / book.wordCount, 0, 1)`, which is 1 whenever Automatic reports a passed book.
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

Layers, back to front: (1) background: the beige gradient **or**, for books without art, the original full-card bitmap; (2) book banner art on the right (cover, custom banner, or the default mountains bitmap), (3) the grid reveal over the art, (4) copy on the left and the caption pill, (5) locked treatment.

**Ruling (round 2, reverses the earlier "delete the asset" decision; refined in round 3):** a pure function `BookArtSource.resolve(book:customBannerExists:coverCached:)` returns `.customBanner`, `.cover` or `.defaultBanner`. `.defaultBanner` (every built-in without a custom banner, custom books with no cover/banner or whose cover is not cached yet, and the no-book state) uses the ORIGINAL `momentum-hero-bg` bitmap as its art (`BannerTreatment.defaultBannerImage`, sharp, `scaledToFill`, anchored to its right side where the mountains are, in the same right ~55 % art frame as covers and banners, so it gets the same grid reveal and locked treatment). The imageset is therefore **kept** (restored from `71d59cd^`). The card background is always the native beige gradient.

1. **Beige gradient (books with cover/custom banner).** `DashboardImpactBackground` draws a native `LinearGradient` from `Color(red: 0.98, green: 0.85, blue: 0.74)` (top-left) to `Color(red: 0.99, green: 0.91, blue: 0.83)` (right), sampled from the PNG's left side. For `.defaultBanner` it draws `Image("momentum-hero-bg")` instead (the asset is kept, see the ruling above).
2. **Banner art (`DashboardBookBannerArt`).** The old mountain bitmap is replaced by art derived from the selected book. Source precedence:
   1. the custom banner (`customBannerFile`, §8.2);
   2. the Open Library cover, `-L` size (§8.3);
   3. none (`.defaultBanner`): the original mountains bitmap is the art.

   Treatment:
   - Frame: the right ~55 % of the card, full height, full-bleed to the card's top, right and bottom edges (the card already clips to `cardCornerRadius`). The image is `.scaledToFill()` and clipped. A portrait cover is therefore a landscape crop of its middle; that is expected.
   - **Left-edge fade:** a `.mask` with a horizontal `LinearGradient` that is clear at the art's left edge and fully opaque by ~12 % of the art width (short, so the first grid columns stay visible at low progress).
   - **Grading (round 3):** none. Full-colour cells show the art as is (cover/low-res banners keep their blur); the muted base is `saturation(0.25)` plus a 22 % black veil, tuned so muted art stays recognisable while the difference to full colour is obvious. The copy sits on the beige part of the fade; there is no wash over the art.
   - **Low-resolution handling.** Open Library `-M` is only ~180 px wide and even `-L` is ~500 px, scaled to roughly 420 pt × 190 pt (≈ 840 px wide at 2×). Therefore Open Library covers are always drawn with the blurred treatment: `blur(radius ≈ 10)` on the fill image, slightly over-scaled (≈ 1.15×) so blurred edges don't show transparent fringes at the card edges. Fetch the **`-L`** size for banner use (one file, `<coverID>-L.jpg`; the chip/thumbnail is downscaled from it). Custom banners are drawn sharp when `pixelWidth ≥ 1.5 × artWidth × backingScaleFactor`, otherwise with a lighter blur (≈ 4). The sharp cover therefore appears only in the chip thumbnail and in the Manage/Add rows, never magnified into the banner.
   - The copy never runs over the grid: headline and subtitle wrap at fixed maxima (330 / 270 pt) so they end where the art's short fade begins (~308 pt into a ~682 pt card).
3. **Foreground.** The card body is the copy column (headline wraps at ~330 pt, subtitle at ~270 pt, so the copy only touches the art's faded left edge) with the button row below it. There is no illustration in front of the art, no light pool and no wash over the art. **Round 3 ruling:** the open book, its 0.8-scale tier, the extra wash tier and the narrow-width "book dropped" tier were removed; the layout is a single tier at every width, the art is just art.
4. **Grid reveal over the art.** Spec §8.7. The same art is drawn twice (muted base, full-colour layer masked by the filled cells); locked state draws the art single-layer, no grid.
5. **Locked state:** the background stack gets the same `blur(2.5)`, `saturation(0.78)` and white 0.32 overlay the PNG got before the feature, plus a 0.5 beige wash so the lock prompt stays legible over art. No grid, no caption. **Author's call:** hide the book chip while locked; the locked prompt needs the space.
6. **Fallback.** No cover and no custom banner (every built-in by default, custom books whose cover is missing or still loading, manually added books, and the no-book state): the original mountains bitmap (§8.6 ruling) is the art, anchored to its right side and framed like any other art; the grid is drawn when there is a book.
7. **Placeholder tint.** The chip's placeholder thumbnail (no cover, no banner) uses `coverTint` (§8.1): the average colour (`CIAreaAverage`) of the *active banner source* (custom banner if present, else cover), darkened ~20 %. It is computed once when that image is first stored or downloaded, persisted, and recomputed when the banner is set or removed. Without a `coverTint`, use a deterministic colour from a hash of `id` over a curated palette of 8 cloth colours (oxblood, navy, forest, ochre, …).

### 8.7 Grid colour reveal

Pure logic lives in `VoiceInk/Features/Dashboard/Components/ProgressGrid.swift`; the painting is in `DashboardBookBannerArt`.

- **Cells.** `N = min(book.pagesEquivalent, 240)`; one cell is `pagesPerCell = totalPages / N` pages (exactly one page for books of up to 240 pages). `ProgressGrid.make(totalPages:size:)` picks the column count whose slots are closest to square for the art region (right ~55 % of the card), `rows = ceil(N / columns)`, skipping column counts that would leave an empty trailing column. Surplus slots in the last column are not drawn (exactly `N` cells). Cells fill **column-major**: top to bottom within a column, columns left to right (like the consistency calendar). Each cell is its slot inset by a 1.5 pt gap, drawn as a rounded square (radius 2.5 pt, capped at a quarter of the cell).
- **Reveal.** `p = clamp(words / book.wordCount, 0, 1)` (`DashboardProgressBenchmark.revealRatio`; NaN counts as 0). `filledCells = floor(p · N)` (exact multiples snap, so 1/3 of 3 cells is exactly 1); the next cell gets opacity `frac(p · N)`; `p ≥ 1` fills all `N`.
- **Painting.** Layer 1: the art, `saturation(0.25)` and a 22 % black veil, masked by all cells (the gaps show the beige card). Layer 2: the art in full colour, masked by the cells with their reveal opacity. A 0.5 pt white 0.16 hairline traces every cell. The left fade mask applies to both layers. No white or bright overlay, no light pool.
- **Caption.** A pill in the art's lower-right corner: black 0.45 fill, white 11 pt semibold monospaced-digit text (fixed colours, readable over any art and in dark mode). Text from `ProgressCaption`: "~%@ of %@ pages dictated"; when finished "All %@ pages dictated", or "All %@ pages · %@×" at ≥ 2 repeats, with a green check. `pagesDictated = round(p · T)` and never equals `T` before the book is finished. Hidden until stats have loaded (the grid then shows 0 %).
- **Locked / no book.** Locked: no grid, no caption. No book: art without grid.
- **Accessibility.** The art is hidden from VoiceOver; the caption pill is a single element whose label is the caption text.


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
| `VoiceInk/Features/Dashboard/Components/DashboardHeroCard.swift` | New inputs (`book: DashboardBook?`, `progressRatio`, `bannerImage: NSImage?`, `usesDefaultBanner`, `isCustomBanner`, menu callbacks); single-tier layout (copy left, banner art behind the right ~55 %); `HeroButtonFlow` button row; book chip/menu; `DashboardImpactBackground` is always the beige gradient, the art (cover, custom banner or the default mountains bitmap) is drawn by `DashboardBookBannerArt` with the grid reveal (§8.6, §8.7). |
| `VoiceInk/Assets.xcassets/momentum-hero-bg.imageset/` | Keep (default banner for books without art; round-2 ruling reverses the earlier deletion). |
| `VoiceInk/Localizable.xcstrings` | New strings (estimate subtitle, caption variants, sheet/panel copy, banner copy and import errors, disclosure, bookmark accessibility), with de/fr/zh-Hans. |
| `README.md` | Recommended (owner signed off the privacy trade-off): add a short note under "Privacy First" that transcription stays fully offline and that dashboard book search and banner-by-URL are opt-in online lookups made only when the user uses them. |

New files:
- `Dashboard/State/DashboardBook.swift`
- `Dashboard/State/DashboardBookStore.swift`
- `Dashboard/Services/OpenLibraryBookSearchService.swift`
- `Dashboard/Services/GoogleBooksPageCountService.swift`
- `Dashboard/Services/BookCoverCache.swift`
- `Dashboard/Services/BannerImageImporter.swift`
- `Dashboard/Components/ProgressGrid.swift` (`ProgressGrid`, `GridReveal`, `ProgressCaption`)
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
- `ProgressGridTests`:
  - cell count = `min(totalPages, 240)`; `pagesPerCell`; roughly square cells; `columns × rows ≥ N`; column-major order;
  - reveal: p = 0 → 0 cells, p = 1 → N, 100/600 → ≈ N/6 (±1 cell), fractional next-cell opacity, clamping above 1, NaN/∞ safe;
  - caption pages `round(p·T)`, never "N of N" before finished, "×" only for repeats.
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
- the grid reveal at 0 %, 10 %, 60 %, 100 % and 250 % over a cover, a custom landscape banner and the mountains bitmap; muted vs full colour clearly distinguishable, muted art still recognisable, caption pill legible, dark mode and locked state;
- the banner with: an Open Library cover (blurred treatment), a high-res custom banner, a tiny low-res custom banner, a very light cover, a very dark cover; headline and subtitle stay readable in each at several window widths;
- no cover and no banner → the mountains bitmap as art, with the grid;
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
2. **Auto-fetched covers for built-ins:** built-ins have no cover, so by default they show the mountains bitmap. Fetching real Open Library covers for built-ins (hardcoded `cover_id`s) would look nicer but adds default network traffic, which the anti-goals forbid. Author's call: no. Users can still give a built-in a custom banner (§8.4, Decision 9).
3. **Built-in page counts:** shown as words/275 ("~77 pages" for The Metamorphosis). Real editions differ; acceptable because it is marked "~".
4. **Builder's choices:** the final banner look (blur radius, desaturation, warm tint, fade width, as long as headline and subtitle stay legible), exact colours, the cloth palette, stack depth `S = 14 pt`, and book size. Keep the proportionality rule and the "only hairline distortion" rule intact.
5. **Open Library `User-Agent`** contact string: confirm the URL or email the owner wants published.
