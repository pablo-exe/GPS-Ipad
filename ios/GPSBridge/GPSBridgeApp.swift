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
                    if phase == .background { model.stop(reason: "Detenido al pasar a segundo plano") }
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
                    Text("Conecta el iPad al hotspot del Android y mantén ambas apps visibles. Usa ventanas simultáneas para comprobar Maps.")
                    TextField("IP del Android", text: $model.host)
                        .keyboardType(.decimalPad).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("Dirección IP del Android")
                    SecureField("Código de seis cifras", text: $model.token)
                        .keyboardType(.numberPad).accessibilityLabel("Código de sesión del Android")
                } header: { Text("Conexión local") }
                .disabled(model.running)

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
                .disabled(model.running)

                Section {
                    Button(model.running ? "Detener y limpiar simulación" : "Conectar") {
                        if model.running { model.stop() } else { model.connect() }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }

                Section("Diagnóstico") {
                    LabeledContent("Red") { Text(model.transport) }
                    Text(model.gps).monospacedDigit().textSelection(.enabled)
                    LabeledContent("Inyección") { Text(model.injection) }
                    LabeledContent("Core Location observado") { Text(model.systemLocation).monospacedDigit() }
                    Text("Al detener, perder GPS o pasar a segundo plano se intenta limpiar DVT. Comprueba la ubicación del sistema después de cada prueba.")
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
