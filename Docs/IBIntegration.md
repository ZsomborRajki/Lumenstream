# Interactive Brokers integration plan

Lumenstream talks to **Trader Workstation (TWS)** or **IB Gateway** directly over the
TWS API socket protocol. There is no IB SDK for Swift, so `IBKit` implements the wire
protocol itself on top of Network framework's `NetworkConnection<TCP>`.

> ⚠️ The IB documentation page (interactivebrokers.com/docs/tws-api) returned HTTP 403
> while this plan was written. Message IDs, field layouts and `MIN_SERVER_VER_*`
> constants come from knowledge of the reference clients (Python/Java `ibapi`). Every
> item marked **[verify]** must be checked against the current docs or the official
> `ibapi` source before that phase ships.

## 1. How the protocol works

| Step | Bytes on the wire |
|---|---|
| Client hello | Raw `API\0`, then one frame containing `v100..176` (supported version range) |
| Server hello | Frame: `serverVersion\0connectionTime\0` |
| Start API | Frame: `71\0 2\0 clientId\0 optionalCapabilities\0` |
| Server bootstrap | Unsolicited: `nextValidId` (9), `managedAccounts` (15), farm-status notices (4, codes 2104/2106/2158) |
| Every message | `UInt32` big-endian length + payload of NUL-terminated ASCII fields; field 0 = message ID |

- **Negotiated version gates field layouts.** Nearly every decoder branches on
  `serverVersion` (e.g. error messages drop their version field at `errorTime`).
  `IBMessageDecoder` and `IBRequest.payload(for:)` both take the version as input.
- **Pacing:** TWS disconnects clients sending more than **50 messages/s**. `IBRateLimiter`
  spaces every send by 20 ms.
- **Client IDs:** up to 32 concurrent API clients per TWS; ID collisions get error 326.
- **Ports:** TWS live 7496 / paper 7497, Gateway live 4001 / paper 4002 (seeded as
  `ConnectionProfile`s). TWS must have *Enable ActiveX and Socket Clients* on, the
  device IP in *Trusted IPs* (or 127.0.0.1 for the simulator), and read-only API
  ticked (Lumenstream is a viewer and never places orders).
- **Market data:** without subscriptions, request `reqMarketDataType(3)` (delayed).
  Standard accounts get ~100 concurrent market data lines; the watchlist must cap itself.

### Version strategy

`IBServerVersion.clientMaximum` is pinned at **176**, deliberately below the
protobuf-era server versions (~201+ **[verify]**), where newer TWS builds switch many
messages to protobuf payloads. Advertising a lower max makes the server negotiate the
classic text protocol, so IBKit only has to support one well-understood layout.

Raising it is a deliberate, tested step: bump the constant, add the new
`MIN_SERVER_VER_*` gates to the decoders, extend the fixtures, and later add a
protobuf decoding path (Phase 6).

## 2. Architecture

```
┌──────────────────────── App target (MainActor) ─────────────────────────┐
│ Views read @Observable state via @Environment(LumenstreamModel.self)   │
└───────────────▲─────────────────────────────────────────────────────────┘
                │ observable state (fine-grained: one Quote object per symbol)
┌───────────────┴──── LumenstreamData (MainActor default) ────────────────┐
│ LumenstreamModel   — owns the session, applies IBEvents to state        │
│ Quote / ConnectionState / ServerNotice — UI-facing domain types         │
│ SwiftData: ConnectionProfile, WatchlistSymbol (versioned schema)        │
│ `internal import IBKit` → wire types never leak into the UI             │
└───────────────▲─────────────────────────────────────────────────────────┘
                │ AsyncThrowingStream<IBEvent>        ▼ IBRequest
┌───────────────┴──────────── IBKit (nonisolated) ────────────────────────┐
│ actor IBConnection — NetworkConnection<TCP>, handshake, rate limit      │
│ @concurrent readLoop — frame → IBMessageDecoder → IBEvent               │
│ IBFieldReader/Writer, IBFrame — pure Sendable value types               │
└─────────────────────────────────────────────────────────────────────────┘
```

Rules:
- IBKit has **no main-actor code** and no SwiftUI. It is fully unit-testable with
  `swift test` on macOS.
- Decoding happens **off the main actor**. The main actor only receives small,
  already-decoded `Sendable` events.
- **Request/response correlation** (Phase 2): a `RequestRegistry` inside
  `IBConnection` hands out request IDs and maps them to `AsyncThrowingStream`
  continuations, so callers write `for try await tick in ib.marketData(for: contract)`
  and cancelling the task sends the matching `cancelMktData` automatically.

## 3. Phases

### Phase 1: Session bootstrap ✅ scaffolded
- [x] Framing, field reader/writer, typed-throws protocol errors
- [x] `IBConnection` actor: handshake, `startApi`, rate limiter, `@concurrent` read loop
- [x] Decode `nextValidId`, `managedAccounts`, `currentTime`, error/notice
- [x] `LumenstreamModel.connect(to:)` / `disconnect()`, connection status badge
- [x] Swift Testing suites for wire format and decoders
- [ ] **Smoke test against TWS paper.** Confirm `NetworkConnection` starts on first
      send, that `receive` honours task cancellation, and what happens on TWS restart
- [ ] **[verify]** `MIN_SERVER_VER_ERROR_TIME` (194) and `ADVANCED_ORDER_REJECT` (166)
- [ ] Record real handshake/bootstrap frames as test fixtures (`Tests/Fixtures/*.bin`)

### Phase 2: Request plumbing
- [ ] `RequestRegistry` (ID allocation, per-request continuations, auto-cancel on termination)
- [ ] `IBContract` value type + encoder (conId, symbol, secType, exchange, primaryExchange, currency)
- [ ] `reqContractDetails` → resolve `WatchlistSymbol.contractID`
- [ ] Reconnect policy: exponential backoff, resubscribe active requests, surface
      1100/1101/1102 connectivity notices as `ConnectionState`

### Phase 3: Market data (Watchlist)
- [ ] `reqMktData` / `cancelMktData`; decode `tickPrice`, `tickSize`, `tickString`,
      `tickGeneric`, `tickReqParams`, `marketDataType` **[verify layouts at v176]**
- [ ] Map tick types (1 bid, 2 ask, 4 last, 9 close, 66–75 delayed equivalents) into `Quote`
- [ ] Coalesce ticks: the read loop batches updates per display frame before
      hopping to the main actor, so a burst of 200 ticks costs one hop, not 200
- [ ] Market-data line budget: subscribe only to visible rows (`onScrollVisibilityChange`)

### Phase 4: Account & portfolio
- [ ] `reqAccountSummary` (NetLiquidation, TotalCashValue, BuyingPower, …) → Dashboard tiles
- [ ] `reqPositions` + `reqAccountUpdates` (`portfolioValue`, `accountValue`) → Portfolio
- [ ] `reqPnL` / `reqPnLSingle` → daily P&L
- [ ] Multi-account picker driven by `managedAccounts`

### Phase 5: History & activity
- [ ] `reqHistoricalData` (+ `keepUpToDate` → `historicalDataUpdate`) for symbol charts
- [ ] `reqExecutions`, `reqOpenOrders` (read-only) → Activity
- [ ] `reqMatchingSymbols` → Search
- [ ] Historical-data pacing (no more than 60 requests per 10 minutes) in the registry

### Phase 6: Modern protocol
- [ ] Raise `clientMaximum`, add the new version gates
- [ ] Protobuf message path for server versions that use it **[verify]**; decide between
      the swift-protobuf package or a minimal hand-written decoder
- [ ] Parse frames with `Span`/`RawSpan` instead of `[String]` to avoid per-field allocations

## 4. Testing strategy
- **Unit (Swift Testing, `swift test`):** encoders/decoders against hand-built payloads
  and recorded fixtures; parameterised tests across server versions.
- **Loopback integration:** an `IBTestServer` built on `NetworkListener<TCP>` that
  replays fixture conversations, so the full actor and model can be tested with no TWS running.
- **Manual:** TWS paper account on the Mac, app in the simulator via `127.0.0.1:7497`.
- **Demo mode:** a `DemoFeed` that emits synthetic `IBEvent`s (random-walk quotes),
  used for previews, screenshots and showing the app off without an IB login.
