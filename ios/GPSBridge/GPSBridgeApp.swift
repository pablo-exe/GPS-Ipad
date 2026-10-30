import SwiftUI
import UniformTypeIdentifiers

@main
struct GPSBridgeApp: App {
    @StateObject private var model = ReceiverModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            BridgeView(model: model)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.resume() }
                }
        }
    }
}

struct BridgeView: View {
    @ObservedObject var model: ReceiverModel
    @State private var importing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Conecta al hotspot del Android e inicia aquí la sesión. Después puedes abrir Waze y Spotify: GPS Bridge mantiene la ubicación en segundo plano. No lo cierres desde el selector de apps.")
                    TextField("IP del Android", text: $model.host)
                        .keyboardType(.decimalPad).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("Dirección IP del Android")
                    SecureField("Código de seis cifras", text: $model.token)
                        .keyboardType(.numberPad).accessibilityLabel("Código de sesión del Android")
                } header: { Text("Conexión local") }
                .disabled(model.running || model.stopping)

                Section {
                    Toggle("Inyectar en la ubicación del sistema", isOn: $model.inject)
                    if model.inject {
                        Button(model.pairingReady ? "Cambiar RPPairing" : "Importar RPPairing") { importing = true }
                        Text(model.pairingReady ? "Archivo de emparejamiento importado" : "Necesitas Modo de desarrollador, LocalDevVPN conectado y un RPPairing de este iPad.")
                            .font(.footnote).foregroundStyle(.secondary)
                        TextField("IP LocalDevVPN", text: $model.tunnelIP).keyboardType(.decimalPad)
                            .accessibilityLabel("IP de LocalDevVPN")
                        TextField("Puerto LocalDevVPN", text: $model.tunnelPort).keyboardType(.numberPad)
                            .accessibilityLabel("Puerto de LocalDevVPN")
                    }
                } header: { Text("Inyección DVT") } footer: {
                    Text("DVT transmite latitud y longitud. La precisión indicada pertenece al GPS Android. Recepción y retorno correcto de DVT no prueban por sí solos que Waze use la posición.")
                }
                .disabled(model.running || model.stopping)

                Section {
                    Button(model.running ? "Detener y limpiar simulación" : "Conectar") {
                        if model.running { model.stop() } else { model.connect() }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(model.stopping)
                    if model.stopping { Text("Limpiando simulación…") }
                }

                Section("Diagnóstico") {
                    LabeledContent("Red") { Text(model.transport) }
                    Text(model.health).font(.footnote).monospacedDigit()
                    Text(model.gps).monospacedDigit().textSelection(.enabled)
                    LabeledContent("Inyección") { Text(model.injection) }
                    LabeledContent("Core Location observado") { Text(model.systemLocation).monospacedDigit() }
                    Text("Segundo plano usa ubicación con indicador del sistema. Al perder GPS se limpia DVT y se reintenta; una pausa de GNSS puede interrumpir la navegación. Mantén LocalDevVPN conectado.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("GPS Bridge")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .propertyList]) { result in
                switch result {
                case .success(let url): model.importPairing(url)
                case .failure(let error): model.injection = error.localizedDescription
                }
            }
        }
    }
}
