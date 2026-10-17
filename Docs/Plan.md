# Lumenstream: app plan

A lightweight, read-only **Interactive Brokers viewer** for iOS 27, built as a
**Liquid Glass and modern-SDK showcase** rather than a mass-market product. It
optimises for craft, clarity and modern APIs over broad device or OS support.

- **Toolchain:** Xcode 27.1, Swift 6.4, iOS 27.0 minimum, Swift 6 language mode
- **IB transport:** TWS API socket protocol, see [IBIntegration.md](IBIntegration.md)

## 1. Architecture, modelled on Apple's samples

| Sample idea | Food Truck | Backyard Birds | Lumenstream |
|---|---|---|---|
| Logic in a local package | `FoodTruckKit` | `BackyardBirdsData`, `BackyardBirdsUI` | `Packages/LumenstreamKit` → `IBKit`, `LumenstreamData`, `LumenstreamUI` |
| Single app model in the environment | `FoodTruckModel` | (SwiftData-driven) | `@Observable LumenstreamModel` via `.environment` |
| Persistence | – | SwiftData + `DataGeneration` seeding | SwiftData `VersionedSchema` + `LumenstreamDataContainer` seeding |
| Navigation enum | `Panel` | – | `AppTab` |
| Preview data | `FoodTruckModel.preview` | sample data containers | `LumenstreamModel.preview()` + `PreviewModifier` (`.sampleData` trait) |
| Thin app target | feature folders | feature folders | `App/`, `Navigation/`, one folder per tab, `Settings/` |

```
Lumenstream/                        app target (synchronized folder group)
  App/LumenstreamApp.swift          @main: model in @State, .lumenstreamDataContainer()
  Navigation/                       ContentView (TabView), AppTab, FeatureScreen chrome, bottom accessory
  Dashboard/ Watchlist/ Portfolio/ Activity/ Search/ Settings/
Packages/LumenstreamKit/
  Sources/IBKit/                    wire protocol + NetworkConnection transport (nonisolated)
  Sources/LumenstreamData/          model, domain types, SwiftData (MainActor default)
  Sources/LumenstreamUI/            glass components, theme, preview modifier (MainActor default)
  Tests/IBKitTests/                 Swift Testing
Docs/                               this plan + IB integration plan
```

Dependency direction: **App → LumenstreamUI → LumenstreamData → IBKit**. LumenstreamData
uses `internal import IBKit`, so no wire type is visible to UI code.

## 2. Concurrency and render isolation

"Render isolation" here means **a tick for one symbol must never make SwiftUI do
work for anything else**, and **the main actor does nothing but apply small diffs**.

1. **Off-main decoding:** socket reads and decoding run in IBKit's `@concurrent` read loop.
2. **Coalesced hops:** ticks are batched per display frame before crossing to the
   main actor (Phase 3 of the IB plan).
3. **Fine-grained observation:** each symbol is its own `@Observable Quote`, so a
   watchlist row observes only its own quote and the list itself is never invalidated by price changes.
4. **Nonisolated render code:** shapes, layouts and visual effects (`Sparkline`,
   future `Layout`s and `visualEffect` closures) are `nonisolated` pure value types,
   so SwiftUI may evaluate them off the main thread.
5. **Isolated animation:** ambient motion uses `TimelineView` + `MeshGradient`, which
   redraws itself without touching app state.
6. **Defaults:** app target and UI/Data packages use `MainActor` default isolation plus
   approachable concurrency (`NonisolatedNonsendingByDefault`, `InferIsolatedConformances`).
   Value types meant for cross-actor use are marked `nonisolated`.
7. **Verification:** profile with the SwiftUI and Swift Concurrency instruments, and
   add a debug overlay that counts body evaluations per row at 50+ ticks/s.

## 3. Showcase checklist (APIs confirmed present in the iOS 27.1 SDK)

**Liquid Glass and navigation**
- [x] `glassEffect(_:in:)`, `Glass.regular.tint(_:)`: cards, status capsule
- [x] `TabView` + `Tab` API, `.sidebarAdaptable`, `Tab(role: .search)`
- [x] `tabBarMinimizeBehavior(.onScrollDown)`, `tabViewBottomAccessory` (+ placement environment)
- [x] `scrollEdgeEffectStyle(.soft, for: .top)`
- [ ] `GlassEffectContainer` + `glassEffectID`/`glassEffectUnion` morphing (Dashboard tiles ↔ detail)
- [ ] `.buttonStyle(.glass)` / `.glassProminent`, `ToolbarSpacer`
- [ ] `backgroundExtensionEffect()` for chart headers
- [ ] `matchedTransitionSource` + `.navigationTransition(.zoom)` from watchlist row to symbol detail
- [ ] iOS 27: `NavigationTransition.crossFade`, `ToolbarItem.visibilityPriority(_:)`,
      `PickerStyle.tabs` (chart range picker), `reorderable()`/`reorderContainer` (watchlist
      reorder), `swipeActionsContainer()`

**Data and concurrency**
- [x] `@Observable`, `@Environment(Type.self)`, `@ObservationIgnored`
- [x] Network `NetworkConnection<TCP>` with async `send`/`receive(as:)`/`receive(exactly:)`
- [x] actors, `@concurrent`, typed throws, `internal import`, Swift Testing
- [x] SwiftData `#Unique`, `#Index`, `VersionedSchema`, `SchemaMigrationPlan`
- [x] `PreviewModifier` shared preview context
- [ ] `Observations` async sequence to drive the tick coalescer and widgets from model state
- [ ] iOS 27 SwiftData `ResultsObserver` / `HistoryObserver` (watchlist sync outside views)

**Visualisation and system**
- [x] `MeshGradient` + `TimelineView`, `symbolEffect`, `contentTransition`
- [ ] Swift Charts: line/area with `chartScrollableAxes`, selection, `Chart3D` for the P&L surface experiment
- [ ] Widgets + Live Activity for a pinned symbol (needs an App Group store)
- [ ] App Intents: "What's my P&L?" and "Show AAPL" with Spotlight/Siri
- [ ] Foundation Models (on-device): summarise the day's notices and executions

## 4. Roadmap

| Milestone | Scope | Exit criteria |
|---|---|---|
| **M0: Groundwork** ✅ | Package split, navigation shell, placeholders, IBKit handshake, tests | Builds warning-free; 13 tests green; launches on iOS 27 simulator |
| **M1: Connected** 🚧 | IB Phase 1 smoke test + Phase 2 plumbing, Connection screen polish, reconnect | Connect to TWS paper, see accounts and notices, survive a TWS restart. Implemented and covered by loopback tests (restart included); the manual run against TWS paper is still open |
| **M2: Watchlist** | IB Phase 3, Quote rows, reorder, zoom transition to detail | 20 symbols streaming delayed data, fewer than 1 row body evaluation per tick |
| **M3: Portfolio & Dashboard** | IB Phase 4, glass tiles with morphing, allocation chart | Positions and P&L match TWS |
| **M4: History & Activity** | IB Phase 5, charts, executions, search | Symbol detail chart with live updates |
| **M5: System surfaces** | Widgets, Live Activity, App Intents, Foundation Models summary | Pinned symbol on the Lock Screen |
| **M6: Protocol modernisation** | IB Phase 6 (higher versions, protobuf, Span parsing) | Works against the newest TWS with `clientMaximum` raised |
| **Ongoing: Demo mode** | `DemoFeed` synthetic events | Every screen demoable without IB |

## 5. Conventions
- New screens go in their own folder and wrap content in `FeatureScreen`.
- Every view has a `#Preview(traits: .sampleData)`.
- Wire-protocol code lives only in IBKit, with a test per message layout.
- Read-only by design: no order placement APIs are implemented, and the TWS API should be set to read-only.
- Run `swift test` in `Packages/LumenstreamKit` before committing.
- SwiftLint runs in strict mode (`.swiftlint.yml`, every finding is an error) as the app
  target's first build phase. Run `swiftlint` from the repo root to lint the app and packages.
- Apple's open-source packages (swift-async-algorithms, swift-collections) are fair game
  when they replace hand-rolled code, e.g. `AsyncAlgorithms` for M2's tick coalescing.
