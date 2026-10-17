# Interactive Brokers integration plan

Lumenstream talks to **Trader Workstation (TWS)** or **IB Gateway** directly over the
TWS API socket protocol. There is no IB SDK for Swift, so `IBKit` implements the wire
protocol itself on top of Network framework's `NetworkConnection<TCP>`.

> ⚠️ The IB documentation page (interactivebrokers.com/docs/tws-api) returned HTTP 403
> while this plan was written. Message IDs, field layouts and `MIN_SERVER_VER_*`
> constants come from the reference clients (Python/Java `ibapi`). Every item marked
> **[verify]** must be checked against the current docs or the official `ibapi` source
> before that phase ships.
>
> M1 checked everything IBKit decodes so far (error, contract data, contract data end,
> `reqContractDetails`, `startApi`, every version constant in `IBServerVersion`) against
> a recent copy of the official `pythonclient` (protobuf era, `MIN_SERVER_VER_PROTOBUF = 201`).
> That caught one bug: `ENCODE_MSG_ASCII7` is 153, not 161.

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
protobuf-era server versions (201+, verified), where newer TWS builds switch many
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
- **Request/response correlation** (Phase 2): `IBRequestRegistry` hands out request IDs
  and maps them to `AsyncThrowingStream` continuations. It sits behind a `Mutex`, not
  an actor, so the read loop routes responses without hopping executors. Callers write
  `for try await tick in ib.marketData(for: contract)`, and leaving the loop early sends
  the matching cancel request (e.g. `cancelMktData`) automatically. One-shot requests fail with
  `connectionClosed` when their socket drops; streaming requests are replayed under the
  same ID on the next socket, and after notice 1101.
- **Session supervision:** `IBConnection.sessions(to:policy:)` wraps `connect` in a
  reconnect loop with exponential backoff (`IBReconnectPolicy`: 1 s doubling to 30 s,
  reset after a 30 s healthy session). The first connection is not retried, so a typo
  fails right away. Client-ID collisions (326) stop retrying. TCP keepalive (20 s idle,
  3 × 5 s probes) catches a TWS host that disappears without closing the socket.

### `NetworkConnection` behaviour (measured on macOS 27 / Xcode 27.1)
- **Nothing listening:** the connection parks in `waiting(ECONNREFUSED)`, and `send`
  suspends until its task is cancelled. `TCP.connectionTimeout` doesn't help. IBKit races
  the handshake against the state stream and a 10 s timeout.
- **Peer closes:** the next `receive(exactly:)` returns **empty content** instead of
  throwing, and only the read after that throws (`ENOMSG`). `receive(as: UInt32.self)`
  at end of stream **traps** (`UnsafeRawBufferPointer.load out of bounds`), so frame
  headers are read as bytes and every short read is treated as a close.
- **Cancellation:** a pending `receive` returns empty content when its task is
  cancelled. It honours cancellation, but you have to check for it yourself.
- `send` on a fresh connection starts it; no explicit `start()` needed.

## 3. Phases

### Phase 1: Session bootstrap ✅ scaffolded
- [x] Framing, field reader/writer, typed-throws protocol errors
- [x] `IBConnection` actor: handshake, `startApi`, rate limiter, `@concurrent` read loop
- [x] Decode `nextValidId`, `managedAccounts`, `currentTime`, error/notice
- [x] `LumenstreamModel.connect(to:)` / `disconnect()`, connection status badge
- [x] Swift Testing suites for wire format and decoders
- [x] `NetworkConnection` behaviour on refusal, peer close and cancellation (see above),
      plus TWS-restart handling, covered by `IBTestServer` loopback tests
- [ ] **Smoke test against TWS paper** (manual: connect, accounts, notices, restart TWS)
- [x] Verified `ERROR_TIME` (194), `ADVANCED_ORDER_REJECT` (166); fixed `ENCODE_MSG_ASCII7` (153)
- [ ] Record real handshake/bootstrap frames as test fixtures (`Tests/Fixtures/*.bin`)

### Phase 2: Request plumbing ✅
- [x] `IBRequestRegistry` (ID allocation, per-request continuations, auto-cancel on termination)
- [x] `IBContract` value type + encoder (conId, symbol, secType, exchange, primaryExchange, currency)
- [x] `reqContractDetails` → resolve `WatchlistSymbol.contractID`
- [x] Reconnect policy: exponential backoff, resubscribe active requests, surface
      1100/1101/1102 connectivity notices as `ConnectionState`

### Phase 3: Market data (Watchlist)
- [ ] `reqMktData` / `cancelMktData`; decode `tickPrice`, `tickSize`, `tickString`,
      `tickGeneric`, `tickReqParams`, `marketDataType` **[verify layouts at v176]**
- [ ] Map tick types (1 bid, 2 ask, 4 last, 9 close, 66–75 delayed equivalents) into `Quote`
- [ ] Coalesce ticks: the read loop batches updates per display frame before
      hopping to the main actor, so a burst of 200 ticks costs one hop, not 200
      (candidate: `AsyncAlgorithms`' `chunked(by: .repeating(every:))`)
- [ ] Market data is the first real streaming request: pass `isStreaming: true` and a
      `cancelMktData` factory to `IBConnection.responses(to:cancel:isStreaming:)`
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
- **Loopback integration:** `IBTestServer` (in `Tests/IBKitTests/Support`) is a scripted
  fake TWS on `NetworkListener<TCP>`, bound to 127.0.0.1 with an ephemeral port, so the
  full actor can be tested with no TWS running: handshake, request routing, error notices,
  socket drops, timeouts, client-ID collisions and a mid-session restart.
- **Manual:** TWS paper account on the Mac, app in the simulator via `127.0.0.1:7497`.
- **Demo mode:** a `DemoFeed` that emits synthetic `IBEvent`s (random-walk quotes),
  used for previews, screenshots and showing the app off without an IB login.
