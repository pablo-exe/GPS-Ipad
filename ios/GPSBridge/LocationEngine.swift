// Adapted from Locus, commit 83c8fb324983728e8f44759cfd834dc637ee38b5.
// Copyright (c) 2026 Locus contributors. MIT; see THIRD_PARTY_NOTICES.md.
import Foundation
import idevice

struct InjectionError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Used exclusively by InjectionWorker's serial queue. No UI thread waits for DVT.
final class LocationEngine: DVTSession {
    private var adapter: OpaquePointer?
    private var handshake: OpaquePointer?
    private var remote: OpaquePointer?
    private var simulation: OpaquePointer?
    var isActive: Bool { simulation != nil }

    func connect(pairingPath: String, ip: String, port: UInt16) throws {
        if simulation != nil { return }
        idevice_set_global_timeout(3)
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard ip.withCString({ inet_pton(AF_INET, $0, &address.sin_addr) }) == 1 else {
            throw InjectionError(message: "IP de LocalDevVPN inválida.")
        }
        var pairing: OpaquePointer?
        try check(pairingPath.withCString { rp_pairing_file_read($0, &pairing) },
                  "RPPairing no válido. Genera un archivo Remote pairing para este iPad con idevice_pair.")
        guard let pairing else { throw InjectionError(message: "RPPairing vacío.") }
        defer { rp_pairing_file_free(pairing) }
        do {
            let error = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    tunnel_create_rppairing($0, socklen_t(MemoryLayout<sockaddr_in>.stride),
                                           "GPSBridge", pairing, nil, nil, &adapter, &handshake)
                }
            }
            try check(error, "No se pudo abrir el túnel. Revisa LocalDevVPN, IP/puerto y Modo de desarrollador.")
            try check(remote_server_connect_rsd(adapter, handshake, &remote), "Falló RSD/DVT. Revisa el emparejamiento y los servicios de desarrollo del iPad.")
            try check(location_simulation_new(remote, &simulation), "Servicio LocationSimulation no disponible. Puede faltar preparar/montar la imagen de desarrollador con Xcode o StikDebug.")
            remote = nil // The successful LocationSimulation handle owns the remote server.
            try check(location_simulation_clear(simulation), "No se pudo limpiar la simulación anterior. Estado de ubicación desconocido; verifica Maps antes de reintentar.")
        } catch {
            release()
            throw error
        }
    }

    func set(_ fix: ReceivedFix) throws {
        guard let simulation, let lat = fix.frame.lat, let lon = fix.frame.lon else {
            throw InjectionError(message: "Sin sesión DVT o coordenadas válidas.")
        }
        try check(location_simulation_set(simulation, lat, lon), "DVT no aceptó la posición. Detén y vuelve a conectar.")
    }

    func clear() throws {
        guard let simulation else { release(); return }
        let error = location_simulation_clear(simulation)
        release()
        try check(error, "No se pudo confirmar la limpieza DVT. Estado de ubicación desconocido; revisa Maps y reinicia el iPad si sigue simulada.")
    }

    private func check(_ error: UnsafeMutablePointer<IdeviceFfiError>?, _ message: String) throws {
        if let error { idevice_error_free(error); throw InjectionError(message: message) }
    }

    private func release() {
        if let simulation { location_simulation_free(simulation); self.simulation = nil }
        if let remote { remote_server_free(remote); self.remote = nil }
        if let handshake { rsd_handshake_free(handshake); self.handshake = nil }
        if let adapter { adapter_free(adapter); self.adapter = nil }
    }
}
