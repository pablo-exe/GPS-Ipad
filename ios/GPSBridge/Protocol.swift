import Foundation

enum StreamError: LocalizedError {
    case invalidFrame, oversized
    var errorDescription: String? {
        switch self {
        case .invalidFrame: return "Trama GPS inválida. Revisa que ambas apps sean de la misma versión."
        case .oversized: return "Trama GPS demasiado grande. Conexión cerrada."
        }
    }
}

struct GPSFrame: Decodable {
    let v: Int
    let type: String
    let seq: Int64?
    let lat: Double?
    let lon: Double?
    let accuracy: Double?
    let age_ms: Double?

    func validate() throws {
        guard v == 1 else { throw StreamError.invalidFrame }
        if type == "waiting" { return }
        guard type == "fix", let seq, seq > 0,
              let lat, lat.isFinite, (-90...90).contains(lat),
              let lon, lon.isFinite, (-180...180).contains(lon),
              let accuracy, accuracy.isFinite, accuracy > 0, accuracy <= 100,
              let age_ms, age_ms.isFinite, age_ms >= 0, age_ms < 2500
        else { throw StreamError.invalidFrame }
    }
}

struct ReceivedFix {
    let frame: GPSFrame
    let receivedAt: TimeInterval
    let streamID: UUID
    func age(at now: TimeInterval) -> TimeInterval {
        (frame.age_ms ?? 2500) / 1000 + max(0, now - receivedAt)
    }
    func isFresh(at now: TimeInterval) -> Bool { age(at: now) < 2.5 }
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
