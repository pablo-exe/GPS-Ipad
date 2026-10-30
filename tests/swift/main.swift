import Foundation

func decode(_ text: String) throws -> GPSFrame {
    let frame = try JSONDecoder().decode(GPSFrame.self, from: Data(text.utf8))
    try frame.validate(); return frame
}
func json(_ id: Int64 = 1, seq: Int64 = 1, age: Double = 0) -> String {
    "{\"v\":2,\"type\":\"fix\",\"request_id\":\(id),\"seq\":\(seq),\"lat\":40.4168,\"lon\":-3.7038,\"accuracy\":5,\"age_ms\":\(age)}"
}
func rejected(_ text: String) { do { _ = try decode(text); fatalError("Accepted invalid frame") } catch { } }
let stream = UUID()
let valid = json()
for text in [valid.replacingOccurrences(of: "40.4168", with: "91"), valid.replacingOccurrences(of: "-3.7038", with: "181"),
             json(age: -1), valid.replacingOccurrences(of: "\"accuracy\":5", with: "\"accuracy\":101"),
             valid.replacingOccurrences(of: "\"v\":2", with: "\"v\":1"), #"{"v":2,"type":"fix"}"#] { rejected(text) }
var buffer = LineBuffer()
let partial = try buffer.append(Data(valid.prefix(20).utf8)); precondition(partial.isEmpty)
let lines = try buffer.append(Data((valid.dropFirst(20) + "\n" + valid + "\r\n").utf8)); precondition(lines.count == 2)
for line in lines { let frame = try JSONDecoder().decode(GPSFrame.self, from: line); try frame.validate() }
do { _ = try buffer.append(Data(repeating: 65, count: 4097)); fatalError("Unbounded frame") } catch { }
var terminated = LineBuffer()
do { _ = try terminated.append(Data((String(repeating: "a", count: 4097) + "\n").utf8)); fatalError("Unbounded line") } catch { }

var poll = PollTracker()
precondition(poll.begin(at: 0) == 1); precondition(poll.begin(at: 0.2) == nil)
do { _ = try poll.accept(decode(json(2)), at: 0.1, streamID: stream); fatalError("Unmatched reply") } catch { }
let measured = try poll.accept(decode(json(age: 500)), at: 0.1, streamID: stream)!
precondition(abs(measured.age(at: 0.1) - 0.6) < 0.001)
precondition(measured.isFresh(at: 1.99)); precondition(!measured.isFresh(at: 2.0))
precondition(poll.begin(at: 0.5) == 2)
let duplicate = try poll.accept(decode(json(2)), at: 0.6, streamID: stream)
precondition(duplicate == nil, "Duplicate must not refresh the original GPS age")
precondition(poll.begin(at: 1) == 3)
do { _ = try poll.accept(decode(json(3, seq: 2)), at: 2.6, streamID: stream); fatalError("Delayed TCP data accepted") } catch { }
precondition(poll.begin(at: 3) == 4); precondition(!poll.timedOut(at: 4.99)); precondition(poll.timedOut(at: 5))
var reset = PollTracker(); _ = reset.begin(at: 10)
let resetFix = try reset.accept(decode(json()), at: 10.1, streamID: stream)
precondition(resetFix != nil, "Service restart/new TCP may reset seq")
var old = PollTracker(); _ = old.begin(at: 0)
let aged = try old.accept(decode(json(age: 2200)), at: 0.4, streamID: stream)
precondition(aged == nil, "Source age plus measured RTT exceeds TTL")
var retries = RetryPolicy()
precondition((0..<6).map { _ in retries.nextDelay() } == [1, 2, 4, 8, 8, 8])
retries.reset(); precondition(retries.nextDelay() == 1)

enum FakeError: Error { case disconnected }
final class Clock: @unchecked Sendable { var time: TimeInterval = 0 }
final class FakeDVT: DVTSession {
    var isActive = false
    var sets = 0, connects = 0, clears = 0
    var failConnect = 0, failSet = 0, failClear = 0
    var duringConnect: (() -> Void)?
    func connect(pairingPath: String, ip: String, port: UInt16) throws {
        connects += 1
        if failConnect > 0 { failConnect -= 1; throw FakeError.disconnected }
        isActive = true; duringConnect?()
    }
    func set(_ fix: ReceivedFix) throws {
        if failSet > 0 { failSet -= 1; throw FakeError.disconnected }; sets += 1
    }
    func clear() throws {
        clears += 1; isActive = false
        if failClear > 0 { failClear -= 1; throw FakeError.disconnected }
    }
}
let config = InjectionWorker.Configuration(pairing: "synthetic", ip: "127.0.0.1", port: 1, streamID: stream)
func sample(_ clock: Clock, seq: Int64 = 1, streamID: UUID = stream) throws -> ReceivedFix {
    ReceivedFix(frame: try decode(json(seq: seq)), receivedAt: clock.time, streamID: streamID, transitBound: 0)
}
do {
    let clock = Clock(), engine = FakeDVT()
    let worker = InjectionWorker(engine: engine, now: { clock.time }, report: { _ in })
    worker.mailbox.put(try sample(clock)); worker.step(config); worker.step(config)
    precondition(engine.sets == 1, "No repeated injection of duplicate fix")
    clock.time = 2.5; worker.step(config); precondition(!engine.isActive && engine.clears == 1)
    worker.mailbox.put(try sample(clock, seq: 2)); worker.step(config)
    precondition(engine.connects == 2 && engine.sets == 2, "GNSS recovery rebuilds DVT")
    worker.mailbox.put(nil); worker.step(config); precondition(!engine.isActive)
}
do {
    let clock = Clock(), engine = FakeDVT(); engine.failSet = 1
    let worker = InjectionWorker(engine: engine, now: { clock.time }, report: { _ in })
    worker.mailbox.put(try sample(clock)); worker.step(config)
    precondition(engine.sets == 0 && !engine.isActive)
    worker.step(config); precondition(engine.connects == 1, "DVT backoff prevents tight retry loops")
    clock.time = 1; worker.step(config); precondition(engine.sets == 1 && engine.connects == 2)
}
do {
    let clock = Clock(), engine = FakeDVT()
    let worker = InjectionWorker(engine: engine, now: { clock.time }, report: { _ in })
    worker.mailbox.put(try sample(clock))
    engine.duringConnect = { clock.time = 4 }
    worker.step(config); precondition(engine.sets == 0 && !engine.isActive, "Fix expired during blocking handshake")
}
do {
    let clock = Clock(), engine = FakeDVT()
    let worker = InjectionWorker(engine: engine, now: { clock.time }, report: { _ in })
    worker.mailbox.put(try sample(clock))
    engine.duringConnect = { worker.mailbox.put(nil) }
    worker.step(config); precondition(engine.sets == 0 && !engine.isActive, "Disconnect during handshake cancels injection")
}
do {
    let clock = Clock(), engine = FakeDVT()
    let worker = InjectionWorker(engine: engine, now: { clock.time }, report: { _ in })
    worker.mailbox.put(try sample(clock)); worker.step(config)
    engine.failClear = 1; clock.time = 2.5; worker.step(config)
    clock.time = 3.5; worker.step(config)
    precondition(engine.connects == 2 && !engine.isActive && engine.sets == 1, "Unknown cleanup is retried even without GPS")
    worker.mailbox.put(try sample(clock, streamID: UUID())); worker.step(config)
    precondition(engine.sets == 1, "Other bridge session cannot inject")
}
print("PASS: protocol v2, matched requests, RTT age bound, duplicate expiry, backoff, DVT failure/recovery, stale blocked handshakes, disconnect races and cleanup retry without GPS")
