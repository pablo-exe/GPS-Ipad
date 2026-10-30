# GPS Bridge · 0.2.0

GNSS Android → hotspot Wi-Fi → iPad → DVT → Core Location → Maps/Waze.

Dos apps nativas, sin backend ni historial de trayectos. Android utiliza `GPS_PROVIDER`; iOS usa SwiftUI, Network.framework, Core Location y la FFI `idevice` distribuida por Locus. IPA para dispositivos arm64; no hace falta compilar Rust.

**Estado:** el 30/10/2026 el usuario confirmó con la versión 0.1 la recepción, DVT, la marca «Simulada por software», seguimiento de movimiento/dirección en Maps y Waze, y parada al cortar conexión. La versión 0.2 añade segundo plano, pantalla Android apagada y recuperación automática. La continuidad de esta nueva versión en los dispositivos reales y junto a Spotify requiere repetir las pruebas de abajo; una compilación correcta no demuestra sesiones largas sin cortes.

## Instalar / actualizar

En [Actions → Build MVP](https://github.com/pablo-exe/GPS/actions/workflows/build.yml), abre la última ejecución correcta y descarga sus **Artifacts**:

- **GPS-Sender-Android**: instala `app-debug.apk` en Android **13 o posterior**. Está firmado para pruebas con la clave debug del runner. Si una actualización dice que la firma no coincide, detén la sesión y desinstala la copia anterior antes de instalar.
- **GPS-Bridge-iOS-unsigned**: firma e instala `GPS-Bridge-unsigned.ipa` con [Sideloadly](https://sideloadly.io/), [SideStore](https://sidestore.io/) o tu instalador habitual. Requiere iOS/iPadOS 18 o posterior y Modo de desarrollador. La cuenta Apple, perfil y caducidad de firma los gestiona tu instalador, sin secretos Apple en GitHub.

**Actualiza las dos apps:** 0.2 utiliza protocolo v2 y elimina v1. No mezcles APK e IPA de distintas versiones. Los artefactos caducan a los 14 días; puedes ejecutar el workflow manualmente.

## Preparación única del iPad

1. Activa **Ajustes → Privacidad y seguridad → Modo de desarrollador**.
2. Con [idevice_pair](https://github.com/jkcoxson/idevice_pair/releases) en Windows/macOS, conecta el iPad por USB, desbloquea, acepta Confiar y genera **Remote pairing / RPPairing** para ese mismo dispositivo. Lockdown/SideStore no sirve.
3. Transfiere el archivo privadamente a Archivos del iPad e impórtalo en GPS Bridge. Si actualizas conservando los datos de la app, no hace falta importarlo otra vez. No subas el archivo a GitHub, issues ni logs: contiene material de emparejamiento.
4. Conecta [LocalDevVPN](https://apps.apple.com/app/id6755608044). El endpoint inicial es `10.7.0.1:49152`; ajusta IP/puerto si tu configuración utiliza otros.
5. Si no está disponible `LocationSimulation`, prepara los servicios/imagen de desarrollador con Xcode o tu herramienta habitual. Este proyecto no monta DDI ni hace pairing dentro de la app.

## Empezar una sesión

1. Activa el hotspot Android y conecta el iPad. Desactiva el **apagado automático del hotspot** si el fabricante lo permite.
2. Abre **GPS Sender** y pulsa **Iniciar GPS en segundo plano**. Permite ubicación **precisa mientras se usa la app** y notificaciones. La notificación mantiene visible la sesión y ofrece **Detener GPS**. No se necesita permiso de ubicación «todo el tiempo»: el servicio se inicia desde la app visible.
3. Pulsa **Permitir GPS continuo con pantalla apagada** y acepta la excepción de optimización de batería para esta app. Revisa también las restricciones adicionales de batería del fabricante. El servicio usa un bloqueo parcial de CPU solo durante la sesión; no mantiene la pantalla encendida ni modifica por sí mismo el hotspot.
4. Introduce en **GPS Bridge** la IP local Android y el código mostrado. Si hay varias direcciones, usa la interfaz del hotspot; la dirección «router/puerta de enlace» de esa Wi-Fi en el iPad ayuda a identificarla. No hay una IP universal.
5. Permite **red local** y **ubicación mientras se usa la app** en el iPad. Activa la inyección, revisa RPPairing/LocalDevVPN y pulsa **Conectar**. Si el primer intento abre el permiso de ubicación, concédelo y vuelve a conectar.
6. Comprueba **Red**, **DVT aceptó posición** y **Core Location observado**. Después abre **Waze a pantalla completa** y Spotify como prefieras; GPS Bridge puede quedar minimizado. Android puede bloquearse o apagar su pantalla, permaneciendo encendido con hotspot activo.

En iPadOS se declara background location y se mantienen `CLBackgroundActivitySession` y actualizaciones de Core Location sin pausa automática. El sistema puede mostrar el indicador de ubicación en segundo plano. No se usa audio de mantenimiento ni se modifica `AVAudioSession`, para no reclamar la reproducción de Spotify. El comportamiento final también depende de iPadOS, LocalDevVPN y la firma instalada.

No fuerces el cierre del receptor desde el selector de apps, ni detengas el servicio Android desde el sistema. Si el sistema mata un proceso, no se promete su resurrección automática: vuelve a abrir e iniciar la app afectada. Bloquear/minimizar no equivale a forzar detención. Tras reiniciar Android debes iniciar una sesión nueva y copiar su nuevo código; la IP/túnel del iPad se recuerdan.

## Reconexión y posiciones caducadas

- **Red y DVT se recuperan de forma independiente**, con espera de 1, 2, 4 y como máximo 8 segundos entre fallos consecutivos. Un cambio de ruta de red puede adelantar el siguiente intento LAN. No hace falta pulsar Conectar tras una caída Wi-Fi breve si no has detenido la sesión.
- El código Android permanece durante la sesión del servicio. Apagar/encender Wi-Fi o minimizar la app no lo cambia. Detener y volver a iniciar Android genera un código nuevo; un código incorrecto detiene los intentos del iPad y exige corregirlo.
- Un socket antiguo no bloquea la recuperación: un cliente recién autenticado reemplaza al anterior. Los clientes sin peticiones caducan en 5 segundos; los handshakes tienen un límite total de 3 segundos.
- **Protocolo v2 por petición/respuesta**: iPad solicita la última posición hasta 2 veces por segundo. Cada respuesta debe corresponder a su petición pendiente. Se suma el **RTT completo** a la edad GNSS como cota conservadora del transporte. Respuestas de más de 1,5 s se descartan y se renueva TCP; una petición sin respuesta vence en 2 s.
- Solo se acepta GNSS Android no simulado y con precisión de 0–100 m. **Edad total menor de 2,5 s** (captura Android + cota RTT + tiempo en el receptor). Un duplicado no rejuvenece la posición. No se extrapola dentro de túneles ni se reproduce una cola de coordenadas.
- Al perder GNSS válido o TCP se invalida inmediatamente el buzón y se intenta `stopLocationSimulation`. Cuando vuelve GPS reciente, DVT se reconstruye y continúa automáticamente. Tras un handshake lento se vuelve a leer el buzón antes de inyectar.
- Si falla la limpieza, el estado es **ubicación desconocida**, nunca «restaurada». Durante una sesión abierta se reintenta recuperar DVT y limpiarlo incluso sin GPS. Cada sesión DVT nueva limpia cualquier simulación anterior antes de admitir posiciones.
- Al pulsar **Detener y limpiar simulación**, se solicita tiempo de ejecución para limpiar antes de soltar la sesión de ubicación. Las llamadas FFI tienen timeout de 3 s por operación; varios pasos bloqueantes pueden retrasar la limpieza. El umbral de caducidad no es una garantía del plazo en que iPadOS deja de mostrar el punto anterior. Forzar cierre, perder LocalDevVPN o matar el proceso puede impedir la limpieza.

El diagnóstico muestra edad máxima estimada, RTT de red, reconexiones y respuestas retrasadas descartadas. Comprueba el estado de las apps si Waze deja de seguirte; la red, GNSS o iPadOS pueden interrumpir el puente. Este comportamiento todavía requiere validación sostenida en tu combinación de hardware.

DVT transmite **latitud y longitud**. La precisión es un filtro/diagnóstico Android, no una precisión enviada al sistema. Las apps pueden detectar posiciones simuladas. El código LAN limita conexiones casuales y no cifra TCP: usa un hotspot protegido, sin exponer el puerto 8765 a Internet. RPPairing no sale del iPad.

## Pruebas y aceptación

CI compila ambas apps, ejecuta Android Lint, prueba el servidor sobre TCP real con GNSS sintético y ejercita el receptor/motor de recuperación con un DVT simulado. Comprueba framing, límites, correlación de peticiones, latencia, caducidad, duplicados, sustitución de sockets, reintentos, fallos de limpieza y desconexión durante un handshake bloqueante. Estas pruebas no prueban el servicio DVT de un dispositivo Apple ni su política real de suspensión.

Antes de dar por verificada esta versión en los dispositivos:

- [ ] Iniciar ambas apps, comprobar Core Location, minimizar GPS Bridge y mantener Waze + Spotify al menos 20–30 minutos con movimiento. Verificar que Spotify no se pausa y Waze sigue el punto.
- [ ] Bloquear Android durante ese periodo; comprobar notificación de servicio y continuidad GNSS.
- [ ] Desactivar GNSS y reactivarlo: no seguir inyectando el último punto y recuperar automáticamente.
- [ ] Cortar Wi-Fi/hotspot 10–20 s y restaurarlo con la misma IP/código: limpiar/reconectar sin tocar Conectar.
- [ ] Desconectar/reconectar LocalDevVPN: mostrar el fallo/estado desconocido cuando corresponda y recuperar limpieza + inyección.
- [ ] Detener desde notificación Android y desde el iPad; comprobar Maps después de cada parada. Al empezar una sesión Android nueva, introducir el código nuevo.
- [ ] Probar bloqueo del iPad, restricciones de batería y cierre forzado por separado; anotar versiones exactas de Android, iPadOS, LocalDevVPN y Waze y los límites observados.

No confundas un punto que permanece en pantalla con inyección continua: mira edad, marca de simulación, movimiento real y resultado de limpieza.

## Compilar y recuperar

En Windows puedes compilar APK con JDK 17, SDK Android 35 y Gradle 8.11.1:

```powershell
cd android
gradle :app:assembleDebug :app:lintDebug
```

iOS requiere macOS + Xcode. GitHub Actions cubre la compilación desde Windows. En un Mac:

```sh
python3 scripts/prepare_ios_vendor.py
brew install xcodegen
cd ios
xcodegen generate
open GPSBridge.xcodeproj
```

Selecciona tu equipo de firma para ejecutar en un iPad. El script descarga desde el commit fijo de Locus la FFI arm64 **de dispositivo**, cabecera y módulo, verifica SHA-256 y evita almacenar 95 MB en Git. El parser y el worker se prueban en macOS con Foundation y un DVT falso, sin necesitar esa biblioteca.

Recuperación: detén ambas sesiones y revisa Maps/Core Location. Si no puedes confirmar la limpieza, recupera LocalDevVPN e inicia/detén GPS Bridge; si sigue simulada, reinicia el iPad y verifica. Puedes volver a los [artefactos de la versión 0.1 comprobada](https://github.com/pablo-exe/GPS/actions/runs/41109884058) mientras estén disponibles; APK e IPA deben volver juntos y habrá que restaurar sus limitaciones de primer plano. Desinstalar elimina las apps, no modifica el hotspot ni LocalDevVPN ni otros servicios del workspace.

Licencia MIT; procedencia de la integración en [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
