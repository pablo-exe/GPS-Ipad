<h1 align="center">GPS Bridge</h1>

<p align="center"><strong>El GPS de tu Android, en los mapas de tu iPad.</strong></p>

<p align="center">
  <a href="https://github.com/pablo-exe/GPS/actions/workflows/build.yml"><img src="https://github.com/pablo-exe/GPS/actions/workflows/build.yml/badge.svg" alt="Estado de compilación y pruebas"></a>
  <img src="https://img.shields.io/badge/versi%C3%B3n-0.2.0-168463?style=flat" alt="Versión 0.2.0">
  <a href="LICENSE"><img src="https://img.shields.io/badge/licencia-MIT-273e48?style=flat" alt="Licencia MIT"></a>
</p>

<p align="center">
  <a href="#descargar">Descargar</a> ·
  <a href="#primera-instalacion">Instalación</a> ·
  <a href="#uso-diario">Uso diario</a> ·
  <a href="#estado-del-proyecto">Qué está probado</a> ·
  <a href="#problemas-frecuentes">Ayuda</a>
</p>

![Android envía su GNSS por un hotspot Wi-Fi a GPS Bridge; DVT entrega la posición a Core Location del iPad para Maps y Waze. Diagrama conceptual.](docs/assets/overview.svg)

**GPS Bridge comparte el GNSS real de un Android con la ubicación del sistema del iPad.** No necesitas una app de navegación modificada: Maps y Waze reciben las coordenadas mediante Core Location. El caso de uso es aprovechar el teléfono que ya tienes para dar posición a un iPad, especialmente un modelo Wi-Fi sin GNSS integrado.

Dos apps nativas pequeñas, una conexión local y **sin jailbreak**. El iPad requiere sideload, Modo de desarrollador, un archivo RPPairing y LocalDevVPN. El ordenador se utiliza para preparar e instalar; no actúa como puente durante la sesión.

> [!IMPORTANT]
> **Proyecto experimental, en validación.** El flujo completo hasta Maps/Waze se ha confirmado en un iPad real con la v0.1 en primer plano. La v0.2 añade segundo plano y recuperación automática; sus pruebas de software y Android emulado pasan. **La continuidad prolongada de la v0.2 en un iPad real, junto a Waze/Spotify, sigue pendiente de verificar.**

## Descargar

### Versión 0.2.0

| App | Descargar | Requisitos | Instalación |
| --- | --- | --- | --- |
| **GPS Sender · Android** | [Descargar APK de prueba](https://github.com/pablo-exe/GPS/actions/runs/41124247447/artifacts/13009922067) | Android **13+**, GNSS y hotspot | APK firmado para pruebas · unos **35 KB** |
| **GPS Bridge · iPad/iPhone** | [Descargar IPA sin firmar](https://github.com/pablo-exe/GPS/actions/runs/41124247447/artifacts/13009402948) | iOS/iPadOS **18+**, dispositivo arm64 | Firma y sideload · aproximadamente **1 MB** |

Estos enlaces descargan **ZIP de GitHub Actions**: inicia sesión en GitHub, descomprime y utiliza el `.apk` o `.ipa` de su interior. La IPA incluye checksum SHA-256 y avisos de terceros. No se instala abriéndola en Archivos: hay que firmarla.

**Los artefactos duran 14 días.** Si un enlace ha caducado, abre [Build MVP](https://github.com/pablo-exe/GPS/actions/workflows/build.yml), entra en una ejecución correcta y busca **Artifacts** al final de su resumen. Si no hay archivos vigentes, usa **Run workflow** cuando tengas permiso o [compila desde el código](#compilar).

**Actualiza siempre las dos apps juntas.** La v0.2 utiliza protocolo v2; no es compatible con el protocolo del MVP v0.1.

## Qué hace

- **Android como fuente GNSS.** El teléfono captura la posición y la sirve por la red local del hotspot.
- **Ubicación del sistema en el iPad.** El receptor utiliza el servicio DVT de Apple, a través de LocalDevVPN y `idevice`.
- **Segundo plano preparado.** Android usa un servicio con notificación; el iPad mantiene una sesión de ubicación en segundo plano. La reproducción de audio no se usa como mecanismo de mantenimiento.
- **Recuperación automática.** Red y DVT se reintentan de forma independiente. Las posiciones antiguas y las respuestas retrasadas se descartan.
- **Sin backend del proyecto.** Las coordenadas circulan por tu red local; estas apps no guardan un historial de trayectos.

<a id="primera-instalacion"></a>

## Primera instalación

### 1. Instala las dos apps

**En Android**

1. Descarga y descomprime **GPS-Sender-Android**.
2. Abre `app-debug.apk` y permite la instalación desde esa aplicación si Android lo solicita.
3. Abre **GPS Sender**.

Si Android rechaza una actualización por firma incompatible, detén el GPS y desinstala la versión anterior antes de instalar. Cada runner de CI utiliza su propia clave debug; la app no guarda un recorrido que tengas que migrar.

**En el iPad**

1. Descarga y descomprime **GPS-Bridge-iOS-unsigned** en tu ordenador.
2. Firma e instala `GPS-Bridge-unsigned.ipa` con [Sideloadly](https://sideloadly.io/) —disponible para Windows y macOS—, [SideStore](https://sidestore.io/) o tu herramienta habitual de sideload.
3. Sigue el asistente del instalador con tu cuenta Apple y abre **GPS Bridge** en el iPad.
4. Mantén vigente la firma. El perfil, su caducidad y las renovaciones dependen del método de instalación que uses.

**No necesitas un Mac para probar los artefactos:** GitHub Actions compila la IPA en macOS y puedes firmarla desde Windows. La compilación local de iOS sí necesita un Mac con Xcode.

### 2. Prepara el acceso de desarrollo del iPad

Esta preparación permite que GPS Bridge hable con los servicios de desarrollo **del propio iPad**.

1. Activa **Ajustes → Privacidad y seguridad → Modo de desarrollador** y acepta el reinicio/confirmación si se solicita. Si no aparece, sigue la [guía oficial de Apple](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device) y completa la instalación de desarrollo.
2. Descarga [idevice_pair desde sus Releases oficiales](https://github.com/jkcoxson/idevice_pair/releases) en Windows o macOS.
3. Conecta el iPad por USB, desbloquéalo y acepta **Confiar en este ordenador**.
4. Genera un archivo **Remote pairing / RPPairing** para ese mismo iPad.
5. Transfiérelo privadamente a **Archivos** del iPad. En GPS Bridge, activa **Inyectar en la ubicación del sistema**, pulsa **Importar RPPairing** y selecciónalo.
6. Instala [LocalDevVPN desde el App Store](https://apps.apple.com/app/id6755608044), acepta su configuración y déjalo conectado.
7. Revisa el endpoint del túnel en GPS Bridge. El valor inicial es **`10.7.0.1:49152`**; cámbialo si tu configuración de LocalDevVPN utiliza otro.

> **RPPairing y Lockdown no son intercambiables.** Un archivo Lockdown/SideStore no sirve para esta conexión. Importa **Remote pairing / RPPairing**; no intentes convertirlo cambiando la extensión. Contiene material de emparejamiento: no lo subas al repositorio, a un issue ni a un log público.

Si el túnel conecta pero no está disponible `LocationSimulation`, puede faltar preparar/montar la imagen de desarrollador —DDI—. Usa Xcode o tu herramienta habitual; [StikDebug](https://github.com/StikDebug/StikDebug) es una referencia del ecosistema. **GPS Bridge no monta DDI ni hace el emparejamiento dentro de la app.** Tener RPPairing no garantiza por sí solo que el servicio DVT esté listo.

### 3. Conecta el hotspot y arranca Android

1. Activa **Compartir Internet / Hotspot Wi-Fi** en Android.
2. Conecta el iPad a esa red. Desactiva el apagado automático del hotspot si tu teléfono ofrece esa opción.
3. En GPS Sender, pulsa **Iniciar GPS en segundo plano**.
4. Permite ubicación **precisa mientras se usa la app** y notificaciones. Activa también la ubicación/GPS del teléfono.
5. Pulsa **Permitir GPS continuo con pantalla apagada** y acepta la excepción de optimización de batería. Revisa cualquier restricción adicional del fabricante.
6. Anota la **IP del hotspot** y el **código de sesión de seis cifras** que muestra la app.

La notificación indica que la sesión está activa y ofrece **Detener GPS**. El servicio se inicia desde la app visible; no necesita el permiso de ubicación «todo el tiempo». Después puedes bloquear el teléfono. **Android debe permanecer encendido**, con hotspot y GPS activos.

**¿Hay varias direcciones IP?** Usa la de la interfaz del hotspot, no una de VPN. La dirección **Router / Puerta de enlace** de esa Wi-Fi en el iPad ayuda a identificar el teléfono. No existe una IP universal para todos los Android.

### 4. Comprueba primero la recepción

1. En GPS Bridge, introduce la **IP Android** y el **código**.
2. Permite **red local** y **ubicación mientras se usa la app**. La ubicación se utiliza también para mantener la sesión en segundo plano.
3. Deja la inyección apagada y pulsa **Conectar**. Si se abre el permiso de ubicación en ese intento, concédelo y vuelve a pulsar **Conectar**.
4. Comprueba que aparecen coordenadas recientes y que aumenta el número de posición.
5. Repite con **LocalDevVPN conectado**: el acceso LAN al Android debe seguir funcionando.

Esta fase aísla la red: puedes comprobar la recepción sin RPPairing ni sesión DVT. Si no llegan coordenadas aquí, resuelve primero IP, permisos, hotspot o señal GNSS. Para la primera captura GNSS, prueba en exterior o cerca de una ventana.

### 5. Activa la ubicación del sistema

1. Pulsa **Detener y limpiar simulación** para cerrar la prueba de recepción.
2. Activa **Inyectar en la ubicación del sistema**. Revisa RPPairing, IP/puerto del túnel y LocalDevVPN.
3. Pulsa **Conectar** y comprueba estos tres niveles:

| Diagnóstico | Qué demuestra |
| --- | --- |
| **Red: recibiendo GPS reciente** | El iPad recibe posiciones válidas del Android. |
| **DVT aceptó posición** | El servicio de desarrollo ha aceptado el comando de coordenadas. |
| **Core Location observado: Simulada por software** | El sistema entrega una ubicación marcada como simulada. Comprueba también que sus coordenadas coinciden con Android. |

4. Abre **Maps o Waze** y comprueba que el punto sigue tu movimiento. El resultado visual en la app de navegación completa la comprobación: recibir GPS y obtener un retorno correcto de DVT no bastan por separado.

## Uso diario

Después de la preparación inicial:

1. **Android:** activa hotspot, inicia GPS Sender y copia su código de sesión.
2. **iPad:** conecta a ese hotspot, activa LocalDevVPN y conecta GPS Bridge con la inyección activada.
3. Comprueba posición reciente y Core Location; después **abre Waze normalmente**. GPS Bridge puede quedar minimizado. Puedes usar Spotify sin que el puente reclame una sesión de audio.
4. **Bloquea Android o apaga su pantalla.** El teléfono debe seguir encendido y compartiendo la red.
5. Al terminar, pulsa **Detener y limpiar simulación** en el iPad y **Detener GPS** en Android o en su notificación. Revisa Maps y el resultado de limpieza.

No hace falta mantener una ventana pequeña del receptor abierta en la v0.2. **Minimizar el iPad no es cerrarlo a la fuerza:** no deslices GPS Bridge fuera del selector de apps. En segundo plano, iPadOS puede mostrar su indicador de ubicación.

Si el sistema mata un proceso, abre e inicia la app afectada de nuevo; no se promete recuperación después de una detención forzada. La app recuerda IP/túnel y la elección de inyección. El código Android permanece durante la sesión del servicio; **detenerlo y volver a iniciarlo genera otro código**. Si cambia la IP del hotspot, corrígela en el receptor.

## Capturas

<p align="center">
  <img src="docs/assets/android-session.png" width="260" alt="Captura real del emulador Android: GPS Sender iniciado, IP local, código efímero y batería sin optimización de Doze. Todavía espera al cliente.">
  <img src="docs/assets/android-stopped.png" width="260" alt="Captura real del emulador Android tras detener la sesión: estado Detenido y sin posición activa.">
</p>

<p align="center"><em>Primera captura: servicio iniciado. Segunda captura: sesión detenida.</em></p>

**Capturas reales de un emulador API 35**, procedentes del ensayo automático de la v0.2. Los datos son sintéticos y el código mostrado pertenecía a una sesión de prueba ya terminada. No son fotos del iPad ni prueba visual de Waze en hardware. [Procedencia de las imágenes](docs/assets/README.md).

## Estado del proyecto

Última comprobación documentada: **30 de octubre de 2026**.

| Escenario | Resultado | Alcance de la evidencia |
| --- | --- | --- |
| Android → iPad → DVT → Core Location → Maps/Waze | **Confirmado en hardware** | Prueba comunicada con la **v0.1 en primer plano**: movimiento/dirección y parada al cortar la conexión. |
| APK e IPA v0.2, protocolo y recuperación DVT | **Pruebas automáticas superadas** | [Ejecución verificada](https://github.com/pablo-exe/GPS/actions/runs/41124247447), commit `2f61fad`. La recuperación DVT se ensaya con una sesión falsa, no con un iPad en CI. |
| Android v0.2 con pantalla apagada y Doze | **60/60 muestras recientes** | Emulador API 35, con excepción de batería. También se verifica parada del socket/servicio y liberación del bloqueo de CPU. |
| iPad v0.2 en segundo plano con Waze/Spotify | **Implementado; pendiente de prueba prolongada en hardware** | No se anuncia como continuidad garantizada. |
| Sesiones largas, bloqueo del iPad y distintas versiones de iPadOS | **Pendiente** | Hay que comprobar cada combinación de dispositivo, sistema, VPN y firma. |

El mínimo **iPadOS 18+** es un objetivo de compilación, no una certificación de todas sus versiones: el acceso a los servicios de desarrollo puede cambiar. La IPA también incluye la familia iPhone, aunque el caso de uso que se está validando es iPad.

## Cuando se corta la conexión

| Situación | Comportamiento de la v0.2 |
| --- | --- |
| Corte TCP o pérdida de Wi-Fi | Invalida la posición, intenta limpiar DVT y reconecta con esperas de **1, 2, 4 y hasta 8 s**. Requiere que IP y código sigan siendo correctos. |
| GNSS sin señal, antiguo o impreciso | Deja de inyectar el último punto; espera una posición válida y recupera DVT automáticamente. |
| Fallo del túnel DVT | Recupera la sesión por separado de la red Android. Una sesión nueva limpia cualquier simulación anterior antes de aceptar posiciones. |
| Respuesta TCP retrasada | La descarta: no reproduce una cola de posiciones antiguas. |
| Limpieza DVT fallida | Muestra **estado de ubicación desconocido** y, mientras la sesión sigue abierta, reintenta la limpieza incluso sin GPS. |
| Código incorrecto | Detiene los intentos para que puedas corregirlo. |
| Proceso cerrado a la fuerza, reinicio o hotspot con otra IP | Requiere intervención: vuelve a iniciar la app, revisa IP y copia el código nuevo cuando corresponda. |

**Límite de frescura:** menos de **2,5 s** de edad total estimada, sumando edad de captura en Android, RTT completo como cota conservadora del transporte y tiempo en el receptor. Un duplicado no rejuvenece el GPS. Solo se admiten posiciones Android no simuladas y con precisión horizontal **mayor de 0 y no superior a 100 m**.

Se solicitan posiciones hasta **2 Hz**; el hardware decide la frecuencia GNSS real. Una respuesta de más de **1,5 s** se descarta y una petición sin respuesta vence en **2 s**. Las llamadas DVT tienen timeout de **3 s por operación** y se ejecutan fuera del hilo de interfaz.

**Caducar una posición no garantiza que iPadOS la haya limpiado en ese mismo plazo.** Una llamada bloqueante, un proceso suspendido/cerrado o un túnel roto pueden retrasar o impedir la limpieza. Un punto que permanece en Maps no demuestra que el puente lo siga reinyectando. Si no puedes confirmar el resultado, sigue la recuperación indicada abajo.

## Problemas frecuentes

| Problema | Qué revisar |
| --- | --- |
| No aparece una IP en Android | Activa el hotspot e inicia GPS Sender. Usa la interfaz del hotspot, no VPN. |
| El iPad no recibe datos | Misma Wi-Fi, IP Android correcta, código actual y permiso de **red local**. Prueba primero solo recepción y después con LocalDevVPN activo. |
| «Código incorrecto» | Detén la sesión del iPad y copia el código que muestra el servicio Android actual. Reiniciar ese servicio cambia el código. |
| Android indica «Buscando GPS» | Ubicación/GPS activados, permiso **preciso**, mejor recepción GNSS y batería sin restricciones. La app no acepta datos viejos o de mala precisión. |
| RPPairing no válido | Exporta **Remote pairing** para ese mismo iPad con `idevice_pair`. No uses Lockdown ni cambies una extensión para intentar convertirlo. |
| DVT no conecta | LocalDevVPN activo, IP/puerto correctos, Modo de desarrollador y RPPairing del dispositivo. |
| No está disponible `LocationSimulation` | Revisa la preparación de servicios/DDI con Xcode o tu herramienta de desarrollo. El puente no monta la imagen. |
| Se detiene al minimizar o bloquear | Comprueba v0.2 en ambas apps, permisos de ubicación, notificación/servicio Android, excepción de batería y que no has forzado un cierre. La continuidad real del iPad sigue en validación. |
| Maps no cambia aunque DVT acepte | Revisa **Core Location observado**, coordenadas y marca de simulación. Prueba Maps y Waze por separado; las apps pueden rechazar ubicaciones simuladas. |
| IPA no instala o deja de abrir | Firma/perfil vigentes y método de sideload correcto. Reinstala/renueva siguiendo tu instalador. No es una descarga de App Store. |
| APK rechaza actualizar | La firma debug puede haber cambiado. Detén y desinstala la versión anterior antes de instalar. |

### Recuperar una ubicación de estado desconocido

1. Recupera **LocalDevVPN** y una posición Android reciente.
2. Conecta GPS Bridge y después pulsa **Detener y limpiar simulación**.
3. Comprueba el resultado DVT y la ubicación en Maps. Una limpieza aceptada no garantiza una nueva posición física inmediata en un iPad Wi-Fi sin GNSS.
4. Si no se confirma la limpieza o sigue apareciendo una posición simulada antigua, **reinicia el iPad y comprueba de nuevo**.

## Privacidad y límites

- Las coordenadas se envían por **TCP local**. No hay backend del proyecto ni historial de trayectos en las apps.
- El código de seis cifras limita conexiones casuales; **TCP no va cifrado**. Utiliza un hotspot protegido y no expongas el puerto **8765** a Internet.
- RPPairing permanece en el iPad: copia privada, permisos `0600`, excluida de backup y accesible después del primer desbloqueo para una sesión con pantalla bloqueada.
- DVT recibe **latitud y longitud**. La precisión Android se utiliza para filtrar/diagnosticar, no se transmite como precisión del sistema. No se envían directamente velocidad, rumbo ni altitud por ese método.
- El sistema marca la ubicación como **simulada por software**. Cada app puede interpretarla o rechazarla.
- No se extrapola una posición dentro de un túnel ni se promete continuidad con procesos terminados. Tampoco es un receptor GNSS MFi ni una distribución por App Store.

<details>
<summary><strong>Prueba recomendada en tus dispositivos</strong></summary>

Para validar la v0.2, anota modelo y versión exacta de Android, iPadOS, LocalDevVPN, Waze y método de firma. Comprueba:

- [ ] Recepción y Core Location correctos antes de cambiar de app.
- [ ] GPS Bridge minimizado y Waze/Spotify activos **20–30 minutos**, con movimiento y sin que el puente reclame audio.
- [ ] Android bloqueado durante la sesión, con servicio/notificación activos.
- [ ] GNSS desactivado/reactivado: caducidad, limpieza y recuperación.
- [ ] Wi-Fi/hotspot cortado 10–20 s y restaurado: recuperación con la misma IP/código, o corrección explícita si cambian.
- [ ] LocalDevVPN desconectado/reconectado: fallo visible y recuperación DVT.
- [ ] Parada desde Android/notificación y desde el iPad; revisión de Maps después de cada prueba.
- [ ] Bloqueo del iPad, restricciones de batería y cierre forzado comprobados por separado.

</details>

## Para desarrolladores

### Compilar

```sh
git clone https://github.com/pablo-exe/GPS.git
cd GPS
```

**Android · Windows, Linux o macOS**

Instala **JDK 17**, **Android SDK 35** y **Gradle 8.11.1**. Configura el SDK para Gradle (`ANDROID_HOME` o `android/local.properties`). No necesitas Android Studio si ya dispones de esos componentes.

```sh
cd android
gradle :app:assembleDebug :app:lintDebug
```

Salida: `android/app/build/outputs/apk/debug/app-debug.apk`.

**iOS · macOS con Xcode**

Desde la raíz del repositorio:

```sh
python3 scripts/prepare_ios_vendor.py
brew install xcodegen
cd ios
xcodegen generate
open GPSBridge.xcodeproj
```

Selecciona tu equipo de firma en Xcode y ejecuta en un dispositivo. `prepare_ios_vendor.py` descarga biblioteca, cabecera y módulo desde un **commit fijo de Locus** y verifica SHA-256. La FFI es para **dispositivo arm64**, no para simulador; evita recompilar Rust y guardar sus 95 MB en Git.

Para generar una IPA sin firma, el comando de compilación y el empaquetado están en [el workflow de Actions](.github/workflows/build.yml). La IPA necesita firma antes de instalarse.

### Arquitectura y pruebas

| Pieza | Responsabilidad |
| --- | --- |
| [`GpsService.java`](android/app/src/main/java/es/pablo/gpsbridge/GpsService.java) | GNSS, servicio Android de ubicación, notificación y bloqueo parcial de CPU durante la sesión. |
| [`GpsServer.java`](android/app/src/main/java/es/pablo/gpsbridge/GpsServer.java) | TCP local v2, autenticación y última posición; sustitución de sockets antiguos. |
| [`ReceiverModel.swift`](ios/GPSBridge/ReceiverModel.swift) | Sesión de ubicación en segundo plano, red, reconexiones, permisos y diagnóstico. |
| [`Protocol.swift`](ios/GPSBridge/Protocol.swift) | Framing NDJSON, correlación de peticiones, edad, RTT y reloj que incluye suspensión. |
| [`InjectionWorker.swift`](ios/GPSBridge/InjectionWorker.swift) | Inyección serial, frescura, limpieza y recuperación DVT, con pruebas aisladas. |
| [`LocationEngine.swift`](ios/GPSBridge/LocationEngine.swift) | Adaptador FFI: RPPairing → túnel → RSD → `LocationSimulation`. |

El protocolo v2 responde a **una petición pendiente**, identificada por `request_id`, con la última posición disponible. No envía un historial en cola. La versión anterior se ha retirado.

CI comprueba el servidor con TCP real y datos sintéticos, el parser y el worker Swift con DVT falso, Android Lint y ambas compilaciones. El job `android-runtime` instala el APK en un emulador aislado API 35, inicia desde el botón, fuerza Doze con pantalla apagada y comprueba las 60 muestras, parada y liberación del bloqueo de CPU. La evidencia está en **Android-runtime-evidence** de la [ejecución verificada](https://github.com/pablo-exe/GPS/actions/runs/41124247447).

Las pruebas incluyen duplicados, respuestas retrasadas, caducidad durante handshake o llamada DVT lenta, desconexión, reintentos y limpieza fallida. **CI no ejecuta los servicios DVT de un iPad físico ni comprueba la política de suspensión real de iPadOS.**

## Comunidad

¿Lo has probado? [Abre un issue](https://github.com/pablo-exe/GPS/issues/new) con modelos, versiones, método de instalación, pasos para reproducir y lo que muestran Red/DVT/Core Location. Indica si estabas en primer plano, segundo plano o con pantalla bloqueada. No adjuntes RPPairing, credenciales, códigos activos ni ubicaciones personales.

Para compartir el proyecto tienes una [portada PNG y un borrador de post para Twitter](docs/COMMUNITY.md). La portada es un diagrama conceptual; las capturas Android son reales de emulador. Las pruebas nuevas ayudan a ampliar la matriz de compatibilidad sin confundir lo implementado con lo verificado.

## Créditos y licencia

- [Locus](https://github.com/ChrisMack32/Locus), por la secuencia de conexión DVT adaptada y la FFI distribuida por su proyecto.
- [idevice](https://github.com/jkcoxson/idevice) e [idevice_pair](https://github.com/jkcoxson/idevice_pair), por el acceso a servicios Apple y la creación de RPPairing.
- [LocalDevVPN](https://apps.apple.com/app/id6755608044), por el camino de red hacia el propio dispositivo.

**[MIT](LICENSE)**. Consulta la procedencia y los avisos completos en [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Proyecto independiente, sin afiliación con Apple, Google, Waze, Spotify ni las herramientas citadas.
