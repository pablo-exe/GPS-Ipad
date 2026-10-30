import Foundation

protocol DVTSession: AnyObject {
    var isActive: Bool { get }
    func connect(pairingPath: String, ip: String, port: UInt16) throws
    func set(_ fix: ReceivedFix) throws
    func clear() throws
}

/// All FFI calls use one queue. The synchronous mailbox also invalidates blocked handshakes.
final class InjectionWorker: @unchecked Sendable {
    struct Configuration {
        let pairing: String
        let ip: String
        let port: UInt16
        let streamID: UUID
    }
    let mailbox = FixMailbox()
    private let queue = DispatchQueue(label: "es.pablo.gpsbridge.dvt", qos: .userInitiated)
    private let engine: DVTSession
    private let now: @Sendable () -> TimeInterval
    private let report: @Sendable (String) -> Void
    private var timer: DispatchSourceTimer?
    private var lastSample: UUID?
    private var retry = RetryPolicy()
    private var retryAt: TimeInterval = 0
    private var cleanupUnknown = false

    init(engine: DVTSession, now: @escaping @Sendable () -> TimeInterval = { BridgeClock.now },
         report: @escaping @Sendable (String) -> Void) {
        self.engine = engine; self.now = now; self.report = report
    }
    func start(_ config: Configuration) {
        queue.async { [self] in
            timer?.cancel(); lastSample = nil; retry.reset(); retryAt = 0
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(500))
            timer.setEventHandler { [weak self] in self?.step(config) }
            self.timer = timer; timer.resume()
        }
    }
    func stop(completion: @escaping @Sendable () -> Void = {}) {
        mailbox.put(nil)
        queue.async { [self] in
            timer?.cancel(); timer = nil
            _ = clean("Inyección detenida")
            completion()
        }
    }

    @discardableResult
    private func clean(_ reason: String) -> Bool {
        let active = engine.isActive
        do {
            try engine.clear()
            if active { cleanupUnknown = false; lastSample = nil }
            report(cleanupUnknown ? "Estado de ubicación desconocido · reintentando limpieza" : "\(reason) · sin simulación DVT activa")
            return !cleanupUnknown
        } catch {
            cleanupUnknown = true
            report("Estado de ubicación desconocido · limpieza DVT falló: \(error.localizedDescription)")
            return false
        }
    }

    // Called on the worker queue in the app, synchronously with a fake DVT session in tests.
    func step(_ config: Configuration) {
        let fix = mailbox.get()
        let fresh = fix.map { $0.streamID == config.streamID && $0.isFresh(at: now()) } == true
        if !fresh {
            if engine.isActive {
                if !clean("GPS caducado") { retryAt = now() + retry.nextDelay() }
            }
            // Even without GPS, retry clearing an uncertain simulation after a broken tunnel.
            if cleanupUnknown && now() >= retryAt {
                do {
                    try engine.connect(pairingPath: config.pairing, ip: config.ip, port: config.port)
                    // connect() must clear previous simulation before returning.
                    cleanupUnknown = false
                    if !clean("Limpieza recuperada") { retryAt = now() + retry.nextDelay() }
                } catch {
                    cleanupUnknown = true; retryAt = now() + retry.nextDelay()
                    report("Estado de ubicación desconocido · no se pudo recuperar DVT; nuevo intento en \(Int(retryAt - now())) s")
                }
            }
            return
        }
        guard now() >= retryAt, let fix, fix.sampleID != lastSample else { return }
        do {
            if !engine.isActive {
                report("Conectando DVT · intento \(retry.failures + 1)")
                try engine.connect(pairingPath: config.pairing, ip: config.ip, port: config.port)
                cleanupUnknown = false
            }
            guard let newest = mailbox.get(), newest.streamID == config.streamID, newest.isFresh(at: now()) else {
                if !clean("GPS caducó durante la conexión DVT") { retryAt = now() + retry.nextDelay() }
                return
            }
            let began = now()
            try engine.set(newest)
            lastSample = newest.sampleID; retry.reset(); retryAt = 0
            if !newest.isFresh(at: now()) || mailbox.get().map({ $0.streamID == config.streamID && $0.isFresh(at: now()) }) != true {
                if !clean("GPS caducó durante la inyección") { retryAt = now() + retry.nextDelay() }
            } else { report("DVT aceptó posición \(newest.frame.seq ?? 0) · \(Int((now() - began) * 1000)) ms") }
        } catch {
            cleanupUnknown = true
            let cleaned = clean("DVT interrumpido")
            let delay = retry.nextDelay(); retryAt = now() + delay
            report("\(error.localizedDescription) · \(cleaned ? "simulación detenida" : "estado de ubicación desconocido") · reintento en \(Int(delay)) s")
        }
    }
}
