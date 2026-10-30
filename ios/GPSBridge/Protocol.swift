import Foundation

enum StreamError: LocalizedError {
    case invalidFrame, oversized, unexpectedResponse, slowResponse
    var errorDescription: String? {
        switch self {
        case .invalidFrame: return "Trama GPS inválida. Revisa que ambas apps sean de la misma versión."
        case .oversized: return "Trama GPS demasiado grande. Conexión cerrada."
        case .unexpectedResponse: return "Respuesta sin petición vigente. Se renovará la conexión."
        case .slowResponse: return "Respuesta GPS retrasada. Se descarta y se renueva la conexión."
        }
    }
}

struct GPSFrame: Decodable {
    let v: Int
    let type: String
    let request_id: Int64?
    let session: String?
    let code: String?
    let seq: Int64?
    let lat: Double?
    let lon: Double?
    let accuracy: Double?
    let age_ms: Double?

    func validate() throws {
        guard v == 2 else { throw StreamError.invalidFrame }
        if type == "hello" {
            guard let session, UUID(uuidString: session) != nil else { throw StreamError.invalidFrame }
            return
        }
        if type == "error" {
            guard code == "auth" else { throw StreamError.invalidFrame }
            return
        }
        guard let request_id, request_id > 0 else { throw StreamError.invalidFrame }
        if type == "waiting" { return }
        guard type == "fix", let seq, seq > 0,
              let lat, lat.isFinite, (-90...90).contains(lat),
              let lon, lon.isFinite, (-180...180).contains(lon),
              let accuracy, accuracy.isFinite, accuracy > 0, accuracy <= 100,
              let age_ms, age_ms.isFinite, age_ms >= 0
        else { throw StreamError.invalidFrame }
    }
}

struct ReceivedFix {
    let frame: GPSFrame
    let receivedAt: TimeInterval
    let streamID: UUID
    let transitBound: TimeInterval
    let sampleID = UUID()
    func age(at now: TimeInterval) -> TimeInterval {
        (frame.age_ms ?? 2500) / 1000 + transitBound + max(0, now - receivedAt)
    }
    func isFresh(at now: TimeInterval) -> Bool { age(at: now) < 2.5 }
}

/// A response is usable only for the outstanding request. RTT bounds its transit age.
struct PollTracker {
    private(set) var pendingID: Int64?
    private(set) var sentAt: TimeInterval = 0
    private var nextID: Int64 = 0
    private var lastSeq: Int64 = 0
    private var nextPollAt: TimeInterval = 0
    private(set) var lastRTT: TimeInterval = 0
    mutating func begin(at now: TimeInterval) -> Int64? {
        guard pendingID == nil, now >= nextPollAt else { return nil }
        nextID += 1; pendingID = nextID; sentAt = now; nextPollAt = now + 0.5
        return nextID
    }
    func timedOut(at now: TimeInterval) -> Bool { pendingID != nil && now - sentAt >= 2 }
    mutating func accept(_ frame: GPSFrame, at now: TimeInterval, streamID: UUID) throws -> ReceivedFix? {
        guard let pendingID, frame.request_id == pendingID else { throw StreamError.unexpectedResponse }
        self.pendingID = nil
        lastRTT = max(0, now - sentAt)
        guard lastRTT <= 1.5 else { throw StreamError.slowResponse }
        guard frame.type == "fix", let seq = frame.seq, seq > lastSeq else { return nil }
        lastSeq = seq
        let fix = ReceivedFix(frame: frame, receivedAt: now, streamID: streamID, transitBound: lastRTT)
        return fix.isFresh(at: now) ? fix : nil
    }
}

struct RetryPolicy {
    private(set) var failures = 0
    mutating func nextDelay() -> TimeInterval {
        let delay = min(8, pow(2, Double(min(failures, 3))))
        failures += 1
        return delay
    }
    mutating func reset() { failures = 0 }
}

struct LineBuffer {
    private var pending = Data()
    mutating func append(_ bytes: Data) throws -> [Data] {
        pending.append(bytes)
        var lines = [Data]()
        while let newline = pending.firstIndex(of: 10) {
            guard pending.distance(from: pending.startIndex, to: newline) <= 4096 else { throw StreamError.oversized }
            lines.append(Data(pending[..<newline]))
            pending.removeSubrange(...newline)
        }
        guard pending.count <= 4096 else { throw StreamError.oversized }
        return lines
    }
}

/// Synchronous mailbox: disconnect/staleness can invalidate an in-flight DVT connection.
final class FixMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var fix: ReceivedFix?
    func put(_ fix: ReceivedFix?) { lock.lock(); self.fix = fix; lock.unlock() }
    func get() -> ReceivedFix? { lock.lock(); defer { lock.unlock() }; return fix }
}
