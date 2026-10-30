package es.pablo.gpsbridge;

import android.Manifest;
import android.app.*;
import android.content.*;
import android.content.pm.*;
import android.location.*;
import android.os.*;
import java.io.IOException;
import java.util.Locale;

/** A user-started location service independent of Activity/screen lifecycle. */
public final class GpsService extends Service implements LocationListener {
    public static final String STOP = "es.pablo.gpsbridge.STOP";
    private static final String CHANNEL = "gps-session";
    private static final int NOTIFICATION = 1;
    private static final Object LOCK = new Object();
    private static Snapshot state = new Snapshot(false, "Detenido", "Sin posición GPS", "");
    public record Snapshot(boolean running, String connection, String gps, String token) { }
    public static Snapshot snapshot() { synchronized (LOCK) { return state; } }
    private GpsServer server;
    private LocationManager locations;
    private PowerManager.WakeLock wakeLock;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private long seq;

    @Override public void onCreate() {
        super.onCreate(); locations = (LocationManager) getSystemService(LOCATION_SERVICE);
        NotificationChannel channel = new NotificationChannel(CHANNEL, "GPS compartido", NotificationManager.IMPORTANCE_LOW);
        channel.setDescription("Servicio activo durante la sesión de navegación");
        getSystemService(NotificationManager.class).createNotificationChannel(channel);
    }
    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && STOP.equals(intent.getAction())) { stopSelf(); return START_NOT_STICKY; }
        if (server != null) return START_NOT_STICKY;
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            stopped("Permite ubicación precisa y vuelve a iniciar desde la app."); stopSelf(); return START_NOT_STICKY;
        }
        try {
            String token = GpsServer.newToken();
            synchronized (LOCK) { state = new Snapshot(true, "Esperando iPad", "Buscando GPS reciente", token); }
            startForeground(NOTIFICATION, notification("Esperando iPad"), ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION);
            PowerManager power = getSystemService(PowerManager.class);
            wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "GPSBridge:Navigation");
            wakeLock.acquire(); // Only during this explicit foreground session; released by onDestroy.
            server = new GpsServer(SystemClock::elapsedRealtime, message -> handler.post(() -> {
                if (server == null) return;
                synchronized (LOCK) { state = new Snapshot(true, message, state.gps(), state.token()); }
                if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)
                    getSystemService(NotificationManager.class).notify(NOTIFICATION, notification(message));
            }), token);
            server.start();
            locations.requestLocationUpdates(LocationManager.GPS_PROVIDER, 500, 0, this, Looper.getMainLooper());
        } catch (SecurityException | IOException | IllegalArgumentException e) {
            stopped("No se pudo iniciar GPS: " + e.getMessage()); stopSelf();
        }
        // A process kill needs explicit restart; no unauthorized background resurrection.
        return START_NOT_STICKY;
    }
    private Notification notification(String message) {
        PendingIntent open = PendingIntent.getActivity(this, 0, new Intent(this, MainActivity.class), PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        PendingIntent stop = PendingIntent.getService(this, 1, new Intent(this, GpsService.class).setAction(STOP), PendingIntent.FLAG_IMMUTABLE);
        return new Notification.Builder(this, CHANNEL).setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle("GPS compartido con el iPad").setContentText(message).setContentIntent(open)
            .setOngoing(true).setOnlyAlertOnce(true).setCategory(Notification.CATEGORY_SERVICE)
            .addAction(new Notification.Action.Builder(null, "Detener GPS", stop).build()).build();
    }
    @Override public void onLocationChanged(Location location) {
        if (server == null) return;
        long stamp = location.getElapsedRealtimeNanos() / 1_000_000;
        long age = SystemClock.elapsedRealtime() - stamp;
        if (location.isFromMockProvider() || !location.hasAccuracy() || location.getAccuracy() <= 0 || location.getAccuracy() > 100 || age < 0 || age >= 2500) {
            server.invalidate();
            synchronized (LOCK) { state = new Snapshot(true, state.connection(), "GPS descartado: antiguo, simulado o impreciso", state.token()); }
            return;
        }
        server.publish(new GpsServer.Fix(++seq, location.getLatitude(), location.getLongitude(), location.getAccuracy(), stamp));
        String gps = String.format(Locale.getDefault(), "%.6f, %.6f\nPrecisión: %.0f m · posición %d", location.getLatitude(), location.getLongitude(), location.getAccuracy(), seq);
        synchronized (LOCK) { state = new Snapshot(true, state.connection(), gps, state.token()); }
    }
    @Override public void onProviderDisabled(String provider) {
        if (server != null) server.invalidate();
        synchronized (LOCK) { state = new Snapshot(state.running(), state.connection(), "GPS desactivado · esperando que lo actives", state.token()); }
    }
    private static void stopped(String message) { synchronized (LOCK) { state = new Snapshot(false, message, "Sin posición activa", ""); } }
    @Override public void onDestroy() {
        if (server != null) { server.close(); server = null; }
        try { locations.removeUpdates(this); } catch (SecurityException ignored) { }
        handler.removeCallbacksAndMessages(null);
        if (wakeLock != null && wakeLock.isHeld()) wakeLock.release();
        if (snapshot().running()) stopped("Detenido");
        stopForeground(STOP_FOREGROUND_REMOVE); super.onDestroy();
    }
    @Override public IBinder onBind(Intent intent) { return null; }
}
