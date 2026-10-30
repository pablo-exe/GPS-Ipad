import SwiftUI
import Network
import CoreLocation
import idevice

@MainActor
final class ReceiverModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var host = UserDefaults.standard.string(forKey: "androidHost") ?? ""
    @Published var token = ""
    @Published var tunnelIP = UserDefaults.standard.string(forKey: "tunnelIP") ?? "10.7.0.1"
    @Published var tunnelPort = UserDefaults.standard.string(forKey: "tunnelPort") ?? "49152"
    @Published var inject = UserDefaults.standard.bool(forKey: "inject")
    @Published var running = false
    @Published var stopping = false
    @Published var transport = "Desconectado"
    @Published var injection = "Inyección desactivada"
    @Published var gps = "Sin posición recibida"
    @Published var health = "Sin sesión de red"
    @Published var systemLocation = "Diagnóstico Core Location sin iniciar"
    @Published var pairingReady = false
    private var connection: NWConnection?
    private var buffer = LineBuffer()
    private var poll = PollTracker()
    private var retry = RetryPolicy()
    private var nextAttemptAt: TimeInterval = 0
    private var openedAt: TimeInterval = 0
    private var greeted = false
    private var latest: ReceivedFix?
    private var watchdog: Timer?
    private var runID = UUID()
    private var attemptID = UUID()
    private var attempts = 0
    private var discarded = 0
    private let locations = CLLocationManager()
    private var backgroundSession: CLBackgroundActivitySession?
    private let pathMonitor = NWPathMonitor()
    private var cleanupTask: UIBackgroundTaskIdentifier = .invalid
    private var cleanupID = UUID()
    private var worker: InjectionWorker!
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private var pairingURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("device.rppairing")
    }
    override init() {
        super.init()
        pairingReady = FileManager.default.fileExists(atPath: pairingURL.path)
        if pairingReady {
            // The existing pairing remains readable during a locked navigation session.
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: pairingURL.path)
        }
        locations.delegate = self
        locations.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locations.activityType = .automotiveNavigation
        locations.pausesLocationUpdatesAutomatically = false
        locations.allowsBackgroundLocationUpdates = true
        locations.showsBackgroundLocationIndicator = true
        worker = InjectionWorker(engine: LocationEngine()) { [weak self] message in
            Task { @MainActor [weak self] in self?.injection = message }
        }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                guard let self, self.running, self.connection == nil else { return }
                self.nextAttemptAt = self.now
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "es.pablo.gpsbridge.path"))
    }

    func importPairing(_ url: URL) {
        guard !running, !stopping else { return }
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= 1_048_576 else { throw InjectionError(message: "Archivo vacío o mayor de 1 MB.") }
            var handle: OpaquePointer?
            let error = url.path.withCString { rp_pairing_file_read($0, &handle) }
            if let error { idevice_error_free(error); throw InjectionError(message: "Importa Remote pairing / RPPairing, no Lockdown.") }
            guard let handle else { throw InjectionError(message: "No se pudo leer RPPairing.") }
            rp_pairing_file_free(handle)
            let data = try Data(contentsOf: url)
            try FileManager.default.createDirectory(at: pairingURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: pairingURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: pairingURL.path)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            var destination = pairingURL; try destination.setResourceValues(values)
            pairingReady = true; injection = "RPPairing importado"
        } catch { injection = error.localizedDescription }
    }

    func connect() {
        guard !running, !stopping else { return }
        guard locations.authorizationStatus == .authorizedAlways || locations.authorizationStatus == .authorizedWhenInUse else {
            if locations.authorizationStatus == .notDetermined { locations.requestWhenInUseAuthorization() }
            transport = "Permite ubicación mientras se usa la app y vuelve a conectar. Es necesaria para mantener esta sesión en segundo plano."
            return
        }
        host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        tunnelIP = tunnelIP.trimmingCharacters(in: .whitespacesAndNewlines)
        var address = in_addr(), tunnel = in_addr()
        guard host.withCString({ inet_pton(AF_INET, $0, &address) }) == 1,
              token.count == 6, token.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            transport = "Introduce la IPv4 del hotspot y el código de seis cifras del Android."; return
        }
        guard !inject || pairingReady else { injection = "Importa el RPPairing de este iPad."; return }
        guard let port = UInt16(tunnelPort), port > 0,
              tunnelIP.withCString({ inet_pton(AF_INET, $0, &tunnel) }) == 1 else {
            injection = "IP o puerto LocalDevVPN inválido."; return
        }
        UserDefaults.standard.set(host, forKey: "androidHost")
        UserDefaults.standard.set(tunnelIP, forKey: "tunnelIP")
        UserDefaults.standard.set(tunnelPort, forKey: "tunnelPort")
        UserDefaults.standard.set(inject, forKey: "inject")
        runID = UUID(); running = true; attempts = 0; discarded = 0; latest = nil
        retry.reset(); nextAttemptAt = now
        backgroundSession = CLBackgroundActivitySession()
        locations.startUpdatingLocation()
        if inject {
            worker.start(.init(pairing: pairingURL.path, ip: tunnelIP, port: port, streamID: runID))
            injection = "Esperando GPS reciente"
        } else { injection = "Solo recepción" }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        watchdog = timer; RunLoop.main.add(timer, forMode: .common)
        tick()
    }

    private func openConnection() {
        attempts += 1; attemptID = UUID()
        let id = attemptID
        buffer = LineBuffer(); poll = PollTracker(); greeted = false; openedAt = now
        let tcp = NWProtocolTCP.Options(); tcp.noDelay = true
        let link = NWConnection(host: NWEndpoint.Host(host), port: 8765, using: NWParameters(tls: nil, tcp: tcp))
        connection = link
        transport = "Conectando Android · intento \(attempts)"
        link.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, self.attemptID == id, self.running else { return }
                switch state {
                case .ready:
                    self.send("{\"v\":2,\"token\":\"\(self.token)\"}\n", id: id)
                    self.receive(id)
                case .failed(let error), .waiting(let error): self.reconnect(error.localizedDescription)
                default: break
                }
            }
        }
        link.start(queue: DispatchQueue(label: "es.pablo.gpsbridge.tcp"))
    }
    private func send(_ text: String, id: UUID) {
        connection?.send(content: Data(text.utf8), completion: .contentProcessed { [weak self] error in
            guard let error else { return }
            let message = error.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, self.attemptID == id, self.running else { return }
                self.reconnect(message)
            }
        })
    }
    private func receive(_ id: UUID) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, error in
            Task { @MainActor [weak self] in
                guard let self, self.attemptID == id, self.running else { return }
                do {
                    if let data {
                        for line in try self.buffer.append(data) {
                            let frame = try JSONDecoder().decode(GPSFrame.self, from: line)
                            try frame.validate()
                            try self.handle(frame)
                            guard self.running, self.attemptID == id else { return }
                        }
                    }
                    if let error { self.reconnect(error.localizedDescription) }
                    else if complete { self.reconnect("Android cerró la conexión") }
                    else { self.receive(id) }
                } catch StreamError.slowResponse { self.discarded += 1; self.reconnect("Respuesta GPS retrasada") }
                catch StreamError.unexpectedResponse { self.discarded += 1; self.reconnect("Respuesta de otra petición") }
                catch { self.stop(reason: "Protocolo inválido. Actualiza ambas apps a v0.2: \(error.localizedDescription)") }
            }
        }
    }
    private func handle(_ frame: GPSFrame) throws {
        if frame.type == "error" { stop(reason: "Código incorrecto. Detén, revisa el código Android y vuelve a conectar."); return }
        if !greeted {
            guard frame.type == "hello" else { throw StreamError.invalidFrame }
            greeted = true; transport = "Android conectado · esperando GNSS"; return
        }
        guard frame.type == "fix" || frame.type == "waiting" else { throw StreamError.invalidFrame }
        let fix = try poll.accept(frame, at: now, streamID: runID)
        retry.reset()
        health = "RTT \(Int(poll.lastRTT * 1000)) ms · reconexiones \(max(0, attempts - 1)) · retrasos descartados \(discarded)"
        if frame.type == "waiting" || (frame.age_ms ?? 0) / 1000 + poll.lastRTT >= 2.5 {
            latest = nil; worker.mailbox.put(nil); gps = "Sin GPS válido · esperando recuperación"
            transport = "Android conectado · GNSS sin señal reciente"
        } else if let fix {
            latest = fix; worker.mailbox.put(fix); transport = "Recibiendo GPS reciente"
        }
        updateAge()
    }
    private func tick() {
        guard running else { return }
        updateAge()
        if connection == nil { if now >= nextAttemptAt { openConnection() }; return }
        if !greeted {
            if now - openedAt >= 5 { reconnect("No se completó la conexión en 5 s") }
            return
        }
        if poll.timedOut(at: now) { discarded += 1; reconnect("Sin respuesta GPS en 2 s"); return }
        if let request = poll.begin(at: now) { send("{\"v\":2,\"request_id\":\(request)}\n", id: attemptID) }
    }
    private func updateAge() {
        guard let fix = latest else { return }
        gps = String(format: "%.6f, %.6f\nPrecisión Android: %.0f m · edad máxima %.1f s · posición %lld", fix.frame.lat ?? 0, fix.frame.lon ?? 0, fix.frame.accuracy ?? 0, fix.age(at: now), fix.frame.seq ?? 0)
        if !fix.isFresh(at: now) { worker.mailbox.put(nil); transport = "GPS caducado · esperando posición nueva" }
    }
    private func reconnect(_ reason: String) {
        guard running else { return }
        worker.mailbox.put(nil); latest = nil
        attemptID = UUID(); connection?.stateUpdateHandler = nil; connection?.cancel(); connection = nil
        greeted = false
        let delay = retry.nextDelay()
        nextAttemptAt = now + delay
        transport = "\(reason) · reconexión en \(Int(delay)) s"
        gps = "Sin posición activa · no se conserva el último punto"
    }
    func resume() { if running { tick() } }

    func stop(reason: String = "Desconectado") {
        guard running else { return }
        running = false; stopping = true; attemptID = UUID()
        cleanupID = UUID()
        let id = cleanupID
        worker.mailbox.put(nil)
        connection?.stateUpdateHandler = nil; connection?.cancel(); connection = nil
        watchdog?.invalidate(); watchdog = nil; latest = nil
        transport = reason; gps = "Sin posición activa"
        systemLocation = "Diagnóstico detenido · comprueba Maps al terminar la limpieza"
        cleanupTask = UIApplication.shared.beginBackgroundTask(withName: "ClearDVTSimulation") { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.cleanupID == id, self.stopping else { return }
                self.injection = "Tiempo de limpieza agotado · estado de ubicación desconocido"
                self.finishStop(id)
            }
        }
        worker.stop { [weak self] in Task { @MainActor [weak self] in self?.finishStop(id) } }
    }
    private func finishStop(_ id: UUID) {
        guard stopping, cleanupID == id else { return }
        locations.stopUpdatingLocation(); backgroundSession?.invalidate(); backgroundSession = nil
        stopping = false
        if cleanupTask != .invalid { UIApplication.shared.endBackgroundTask(cleanupTask); cleanupTask = .invalid }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let source = location.sourceInformation?.isSimulatedBySoftware == true ? "Simulada por software" : "Sin marca de simulación"
        let message = String(format: "%@\n%.6f, %.6f · edad %.1f s", source, location.coordinate.latitude, location.coordinate.longitude, max(0, -location.timestamp.timeIntervalSinceNow))
        Task { @MainActor [weak self] in if self?.running == true { self?.systemLocation = message } }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let denied = manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
        Task { @MainActor [weak self] in if denied { self?.stop(reason: "Permiso de ubicación revocado. Revisa Ajustes.") } }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = "Core Location: \(error.localizedDescription)"
        Task { @MainActor [weak self] in if self?.running == true { self?.systemLocation = message } }
    }
}
