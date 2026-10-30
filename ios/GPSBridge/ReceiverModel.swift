import SwiftUI
import Network
import CoreLocation
import UniformTypeIdentifiers
import idevice

@MainActor
final class ReceiverModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var host = ""
    @Published var token = ""
    @Published var tunnelIP = "10.7.0.1"
    @Published var tunnelPort = "49152"
    @Published var inject = false
    @Published var running = false
    @Published var transport = "Desconectado"
    @Published var injection = "Inyección desactivada"
    @Published var gps = "Sin posición recibida"
    @Published var systemLocation = "Diagnóstico Core Location sin iniciar"
    @Published var pairingReady = false
    private var connection: NWConnection?
    private var buffer = LineBuffer()
    private var lastSeq: Int64 = 0
    private var latest: ReceivedFix?
    private var lastBytesAt: TimeInterval = 0
    private var watchdog: Timer?
    private var session = UUID()
    private let locations = CLLocationManager()
    private var worker: InjectionWorker!

    private var pairingURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("device.rppairing")
    }

    override init() {
        super.init()
        pairingReady = FileManager.default.fileExists(atPath: pairingURL.path)
        locations.delegate = self
        locations.desiredAccuracy = kCLLocationAccuracyBest
        worker = InjectionWorker { [weak self] message in
            Task { @MainActor [weak self] in self?.injection = message }
        }
    }

    func importPairing(_ url: URL) {
        guard !running else { return }
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= 1_048_576 else { throw InjectionError(message: "Archivo vacío o mayor de 1 MB.") }
            var handle: OpaquePointer?
            let error = url.path.withCString { rp_pairing_file_read($0, &handle) }
            if let error { idevice_error_free(error); throw InjectionError(message: "No es un RPPairing válido. Exporta Remote pairing, no Lockdown, con idevice_pair.") }
            guard let handle else { throw InjectionError(message: "No se pudo leer el emparejamiento.") }
            rp_pairing_file_free(handle)
            let data = try Data(contentsOf: url)
            try FileManager.default.createDirectory(at: pairingURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: pairingURL, options: [.atomic, .completeFileProtection])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: pairingURL.path)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            var destination = pairingURL; try destination.setResourceValues(values)
            pairingReady = true
            injection = "RPPairing importado en este dispositivo"
        } catch { injection = error.localizedDescription }
    }

    func connect() {
        guard !running else { return }
        let address = host.trimmingCharacters(in: .whitespacesAndNewlines)
        var parsedAddress = in_addr()
        guard address.withCString({ inet_pton(AF_INET, $0, &parsedAddress) }) == 1,
              token.count == 6, token.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            transport = "Introduce la IPv4 del hotspot y el código de seis cifras del Android."
            return
        }
        guard !inject || pairingReady else { injection = "Importa primero el RPPairing de este iPad."; return }
        guard let port = UInt16(tunnelPort), port > 0 else { injection = "Puerto de LocalDevVPN inválido."; return }
        session = UUID()
        let id = session
        running = true
        UIApplication.shared.isIdleTimerDisabled = true
        buffer = LineBuffer(); latest = nil; lastSeq = 0
        lastBytesAt = ProcessInfo.processInfo.systemUptime
        transport = "Conectando al Android…"
        if inject { worker.start(pairing: pairingURL.path, ip: tunnelIP, port: port, streamID: id); injection = "Esperando GPS reciente" }
        else { injection = "Solo recepción · inyección desactivada" }
        locations.requestWhenInUseAuthorization()
        locations.startUpdatingLocation()
        let link = NWConnection(host: NWEndpoint.Host(address), port: 8765, using: .tcp)
        connection = link
        link.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, self.session == id, self.running else { return }
                switch state {
                case .ready:
                    self.transport = "Conectado · esperando GPS"
                    let hello = Data("{\"v\":1,\"token\":\"\(self.token)\"}\n".utf8)
                    link.send(content: hello, completion: .contentProcessed { error in
                        if let error { Task { @MainActor [weak self] in
                            guard self?.session == id else { return }
                            self?.stop(reason: error.localizedDescription)
                        } }
                    })
                    self.receive(id)
                case .failed(let error): self.stop(reason: "Error de red: \(error.localizedDescription)")
                case .waiting(let error): self.transport = "Esperando red: \(error.localizedDescription)"
                default: break
                }
            }
        }
        link.start(queue: DispatchQueue(label: "es.pablo.gpsbridge.tcp"))
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkAge() }
        }
    }

    private func receive(_ id: UUID) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, error in
            Task { @MainActor [weak self] in
                guard let self, self.session == id, self.running else { return }
                do {
                    if let data, !data.isEmpty {
                        self.lastBytesAt = ProcessInfo.processInfo.systemUptime
                        for line in try self.buffer.append(data) {
                            let frame = try JSONDecoder().decode(GPSFrame.self, from: line)
                            try frame.validate()
                            if frame.type == "waiting" {
                                self.latest = nil; self.worker.mailbox.put(nil)
                                self.transport = "Android conectado · esperando señal GPS reciente"
                                self.gps = "Sin posición GPS válida"
                            } else if let seq = frame.seq, seq > self.lastSeq {
                                self.lastSeq = seq
                                let fix = ReceivedFix(frame: frame, receivedAt: ProcessInfo.processInfo.systemUptime, streamID: id)
                                self.latest = fix
                                self.worker.mailbox.put(fix)
                                self.transport = "Recibiendo GPS del Android"
                                self.checkAge()
                            }
                        }
                    }
                    if let error { self.stop(reason: "Conexión interrumpida: \(error.localizedDescription)") }
                    else if complete { self.stop(reason: "Android cerró la conexión. Revisa su app y el código.") }
                    else { self.receive(id) }
                } catch { self.stop(reason: error.localizedDescription) }
            }
        }
    }

    private func checkAge() {
        guard running else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastBytesAt > 5 { stop(reason: "Android no responde. Revisa hotspot, IP y código; vuelve a conectar."); return }
        if let fix = latest {
            gps = String(format: "%.6f, %.6f\nPrecisión Android: %.0f m · edad %.1f s · posición %lld", fix.frame.lat ?? 0, fix.frame.lon ?? 0, fix.frame.accuracy ?? 0, fix.age(at: now), fix.frame.seq ?? 0)
            if !fix.isFresh(at: now) { worker.mailbox.put(nil); transport = "GPS caducado · inyección detenida" }
        }
    }

    func stop(reason: String = "Desconectado") {
        guard running else { return }
        running = false
        session = UUID()
        worker.stop()
        connection?.cancel(); connection = nil
        watchdog?.invalidate(); watchdog = nil
        latest = nil
        locations.stopUpdatingLocation()
        UIApplication.shared.isIdleTimerDisabled = false
        transport = reason
        gps = "Sin posición activa"
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let source = location.sourceInformation?.isSimulatedBySoftware == true ? "Simulada por software" : "Sin marca de simulación"
        let message = String(format: "%@\n%.6f, %.6f · edad %.1f s", source, location.coordinate.latitude, location.coordinate.longitude, max(0, -location.timestamp.timeIntervalSinceNow))
        Task { @MainActor [weak self] in self?.systemLocation = message }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = "Core Location: \(error.localizedDescription)"
        Task { @MainActor [weak self] in self?.systemLocation = message }
    }
}
