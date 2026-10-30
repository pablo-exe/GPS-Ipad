# GPS Bridge · MVP

GPS real de Android → hotspot Wi-Fi → app iPad → servicio de simulación DVT → ubicación del sistema.

Dos apps nativas pequeñas, sin backend, mapas, rutas, publicidad ni servicios de segundo plano. Android usa `GPS_PROVIDER`; iOS usa SwiftUI, Network.framework y la FFI `idevice` que distribuye Locus. No hace falta compilar Rust.

**Alcance:** experimento de viabilidad en primer plano. Compilar, recibir coordenadas y que DVT devuelva éxito son comprobaciones diferentes. Maps/Waze y la convivencia hotspot + LocalDevVPN se deben verificar en el iPad real. El MVP no monta imágenes de desarrollador ni implementa emparejamiento dentro de la app.

## Descargar e instalar

Abre [Actions → Build MVP](https://github.com/pablo-exe/GPS/actions/workflows/build.yml), entra en una ejecución correcta y descarga sus **Artifacts** (requiere iniciar sesión en GitHub):

- **GPS-Sender-Android**: descomprime e instala `app-debug.apk`. Android puede pedir permitir instalaciones desde esa aplicación. Está firmado con la clave debug del runner; para actualizar desde otra ejecución puede ser necesario desinstalar la copia anterior. No guarda datos de usuario.
- **GPS-Bridge-iOS-unsigned**: descomprime `GPS-Bridge-unsigned.ipa`. Está compilada para dispositivos arm64, **sin firma**. Fírmala e instálala con [Sideloadly](https://sideloadly.io/), [SideStore](https://sidestore.io/) o el método de sideload que utilices. No basta con abrir la IPA en Archivos. La firma, el perfil y su caducidad los gestiona el instalador con tu cuenta Apple. Activa Modo de desarrollador.

Las compilaciones no necesitan certificados ni secretos Apple en GitHub. Los artefactos caducan a los 14 días; puedes volver a ejecutar el workflow manualmente.

## Primera prueba: solo recepción

1. Activa **compartir Internet / hotspot** en Android y conecta el iPad a esa red.
2. Abre **GPS Sender** en Android. Pulsa **Iniciar GPS** y permite **ubicación precisa mientras se usa la app**. Para captar GNSS, prueba cerca de una ventana o en exterior.
3. La pantalla muestra las IPv4 locales y un código nuevo de seis cifras. Usa la dirección de la interfaz del hotspot, no una de VPN. Si hay varias, prueba la que aparece como puerta de enlace/router de esa Wi-Fi en el iPad; no hay una IP universal para todos los Android.
4. Abre **GPS Bridge** en el iPad. Permite acceso a **red local**. Introduce esa IP y el código. Deja la inyección apagada y pulsa **Conectar**.
5. Las coordenadas y el número de posición deben actualizarse. Esta prueba funciona sin RPPairing ni túnel DVT. Repítela también con LocalDevVPN conectado: comprueba así que la VPN conserva el acceso LAN.

Mantén las dos apps abiertas. Android mantiene la pantalla encendida durante el envío. Al poner cualquiera en segundo plano se detiene su parte de la sesión; hay que iniciar/conectar de nuevo.

## Segunda prueba: ubicación del sistema

Preparación única:

1. Activa **Ajustes → Privacidad y seguridad → Modo de desarrollador** en el iPad; acepta el reinicio si se solicita.
2. En Windows o macOS, descarga [idevice_pair](https://github.com/jkcoxson/idevice_pair/releases). Conecta el iPad por USB, desbloquéalo y acepta **Confiar**.
3. Genera un archivo **Remote pairing / RPPairing** para ese mismo iPad. Un archivo Lockdown/SideStore no sirve. Transfiérelo de forma privada a Archivos en el iPad. **Contiene material de emparejamiento: no lo subas al repositorio, a issues ni a logs.**
4. Instala y conecta [LocalDevVPN](https://apps.apple.com/app/id6755608044). La configuración inicial del MVP es `10.7.0.1:49152`; ajusta ambos campos si tu versión usa otros valores.
5. Si DVT informa de que falta `LocationSimulation`, prepara los servicios/imagen de desarrollador con Xcode o con tu herramienta habitual (por ejemplo StikDebug). Tener un RPPairing no demuestra que DVT esté listo. Este MVP muestra el fallo y no añade un montador DDI.

Prueba:

1. Detén la recepción en GPS Bridge. Activa **Inyectar en la ubicación del sistema** e **Importar RPPairing**. Selecciona el archivo anterior. La app valida su formato con `idevice` y guarda una copia privada, protegida y excluida de copias de seguridad.
2. Inicia Android, revisa IP/código y pulsa **Conectar** en el iPad.
3. Comprueba los tres niveles del diagnóstico: **Red**, **DVT aceptó posición** y **Core Location observado**. Permite ubicación mientras se usa GPS Bridge para este último diagnóstico. El campo de Core Location muestra la marca de simulación y coordenadas que realmente entrega el sistema.
4. En el iPad abre **Maps o Waze junto a GPS Bridge**, con ventanas simultáneas / Split View según tu versión de iPadOS. GPS Bridge debe seguir visible; cambiar a otra app a pantalla completa puede enviarlo a segundo plano y detenerlo. Comprueba que el punto sigue al Android al caminar. Si tu modo de ventanas no mantiene el receptor ejecutándose, usa primero el diagnóstico Core Location de la propia app.
5. Pulsa **Detener y limpiar simulación**. Revisa el resultado DVT y Maps. Una limpieza aceptada no garantiza una nueva posición física inmediata en un iPad Wi-Fi sin GNSS.

La única aceptación de viabilidad completa es observar en el dispositivo que Core Location y Maps/Waze siguen al GNSS Android. No se afirma todavía continuidad en segundo plano, bloqueo de pantalla o conducción.

## Pérdidas de señal y límites

- Android solicita GNSS cada 500 ms; el hardware decide la frecuencia real. TCP envía la posición más reciente cada 500 ms. iOS inyecta cada **posición nueva**, como máximo a 2 Hz; los duplicados no refrescan su caducidad.
- Solo admite posiciones no simuladas en Android, precisión de 0–100 m y edad menor de **2,5 s**. Esa edad combina el tiempo monotónico desde la captura en Android y desde la recepción en iOS. No incluye el tránsito de red no medido: una pausa de TCP puede añadir latencia. Se comprueba expresamente al probar en hardware.
- Sin GPS reciente se invalida el buzón y se intenta `stopLocationSimulation`. Al cerrar el TCP o detener se hace lo mismo. Sin tráfico durante 5 s se cierra la recepción. No hay reconexiones automáticas ni historial de coordenadas.
- DVT corre en una cola independiente, con timeout de la librería de 3 s por operación. Un handshake o llamada bloqueante puede retrasar la limpieza; 2,5 s es el umbral de caducidad, **no una garantía de que iPadOS haya limpiado en ese plazo**.
- Si falla la limpieza, la pantalla indica **estado de ubicación desconocido**. Comprueba Maps; reconecta LocalDevVPN y la app para abrir una sesión que primero limpia DVT. Si sigue simulada, reinicia el iPad y verifica de nuevo.
- DVT recibe **solo latitud y longitud**. La precisión se usa para filtrar y diagnosticar; no se transmite como precisión del sistema. Las apps pueden detectar o rechazar ubicaciones simuladas.
- El código de seis cifras limita conexiones casuales, sin cifrar TCP. Úsalo en tu hotspot protegido y no redirijas el puerto 8765 a Internet. El emparejamiento Apple nunca se transmite al Android. Solo un cliente TCP simultáneo.

## Compilar

**Windows local:** el APK se puede compilar con JDK 17, Android SDK 35 y Gradle 8.11.1. No se necesita Android Studio si ya tienes esos componentes:

```powershell
cd android
gradle :app:assembleDebug :app:lintDebug
```

**iOS:** se necesita macOS con Xcode y su SDK. Desde este PC Windows, el runner macOS de GitHub Actions es la opción directa. En un Mac local puedes generar y abrir el proyecto, seleccionar tu equipo Apple y ejecutar en el iPad:

```sh
python3 scripts/prepare_ios_vendor.py
brew install xcodegen
cd ios
xcodegen generate
open GPSBridge.xcodeproj
```

El script descarga la FFI arm64 para **dispositivo**, no simulador, desde un commit fijo de Locus y valida SHA-256 de biblioteca, cabecera y módulo. El repositorio no almacena sus 95 MB ni necesita recompilarla. Las pruebas del parser son Foundation puro y se ejecutan en macOS sin esa FFI.

## Validación y vuelta atrás

CI compila APK + IPA, ejecuta Android Lint, una prueba TCP real con coordenadas sintéticas y pruebas Swift de framing, rangos, buffers y caducidad. Estas pruebas no ejercitan RPPairing, LocalDevVPN, DVT ni GNSS físicos.

Lista de aceptación manual:

- [ ] Android obtiene GNSS reciente; el iPad recibe el mismo punto por hotspot.
- [ ] La recepción continúa con LocalDevVPN conectado.
- [ ] RPPairing abre DVT y Core Location observa las coordenadas inyectadas.
- [ ] Maps sigue al Android; repetir con Waze y anotar versiones exactas.
- [ ] Detener Android, desactivar GPS y desconectar Wi-Fi provocan caducidad/limpieza, sin seguir reinyectando el último punto.
- [ ] Detener GPS Bridge y mandarlo a segundo plano limpian la simulación; comprobar también el cierre forzado, donde no se garantiza ejecutar código de limpieza.
- [ ] Después de cada prueba y tras reiniciar, Maps vuelve a una ubicación no simulada o deja de mostrar un punto simulado antiguo.

Recuperación: detener ambas apps, revisar Maps/Core Location, desconectar LocalDevVPN y reiniciar el iPad si persiste una simulación. Desinstalar ambas apps elimina el MVP; el hotspot, Modo de desarrollador y LocalDevVPN se gestionan desde Ajustes. No se cambia ningún servicio del resto del workspace.

Licencia MIT. Procedencia de la integración y dependencias en [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
