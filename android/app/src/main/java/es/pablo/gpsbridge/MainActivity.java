package es.pablo.gpsbridge;

import android.Manifest;
import android.app.Activity;
import android.content.pm.PackageManager;
import android.location.*;
import android.os.*;
import android.view.*;
import android.widget.*;
import java.net.*;
import java.util.*;

public final class MainActivity extends Activity implements LocationListener {
    private LocationManager locations;
    private GpsServer server;
    private TextView connection, gps, endpoint;
    private Button toggle;
    private long seq;
    private final Handler ui = new Handler(Looper.getMainLooper());
    private final Runnable refresh = new Runnable() {
        public void run() {
            if (server == null) return;
            endpoint.setText("Direcciones Android (puerto 8765)\n" + addresses() + "\n\nCódigo de sesión: " + server.token);
            ui.postDelayed(this, 2000);
        }
    };

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        locations = (LocationManager) getSystemService(LOCATION_SERVICE);
        ScrollView scroll = new ScrollView(this);
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        int space = (int) (24 * getResources().getDisplayMetrics().density);
        content.setPadding(space, space, space, space);
        content.setOnApplyWindowInsetsListener((view, insets) -> {
            view.setPadding(space, space + insets.getSystemWindowInsetTop(), space, space + insets.getSystemWindowInsetBottom());
            return insets;
        });
        scroll.addView(content);
        TextView title = label(content, "Compartir GPS", 28);
        title.setAccessibilityHeading(true);
        label(content, "Activa el hotspot y conecta el iPad a él. Mantén esta app abierta y permite ubicación precisa.", 17);
        toggle = new Button(this);
        toggle.setText("Iniciar GPS");
        toggle.setOnClickListener(v -> { if (server == null) requestStart(); else stop(); });
        content.addView(toggle);
        connection = label(content, "Detenido", 20);
        endpoint = label(content, "La dirección y el código aparecerán al iniciar.", 17);
        endpoint.setTextIsSelectable(true);
        gps = label(content, "Sin posición GPS", 17);
        label(content, "Solo primer plano. Al salir de la app se detiene el envío. No se guarda el recorrido ni se usa un servidor externo.", 15);
        setContentView(scroll);
    }

    private TextView label(LinearLayout parent, String text, int size) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextSize(size);
        view.setTextColor(0xff17252b);
        int p = (int) (12 * getResources().getDisplayMetrics().density);
        view.setPadding(0, p, 0, p);
        parent.addView(view);
        return view;
    }

    private void requestStart() {
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION}, 1);
            return;
        }
        start();
    }

    @Override public void onRequestPermissionsResult(int request, String[] permissions, int[] results) {
        super.onRequestPermissionsResult(request, permissions, results);
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) start();
        else connection.setText("Hace falta ubicación precisa. Actívala en Ajustes → Aplicaciones → GPS Sender → Permisos.");
    }

    private void start() {
        if (server != null) return;
        if (!locations.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
            connection.setText("Activa la ubicación del Android y vuelve a iniciar.");
            return;
        }
        try {
            GpsServer current = new GpsServer(SystemClock::elapsedRealtime, message -> runOnUiThread(() -> {
                if (server != null) connection.setText(message);
            }));
            server = current;
            seq = 0;
            locations.requestLocationUpdates(LocationManager.GPS_PROVIDER, 500, 0, this, Looper.getMainLooper());
            current.start();
            toggle.setText("Detener GPS");
            connection.setText("Esperando iPad y señal GPS");
            getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
            refresh.run();
        } catch (SecurityException e) {
            stop();
            connection.setText("Permiso de ubicación revocado. Actívalo en Ajustes y vuelve a iniciar.");
        } catch (Exception e) {
            stop();
            connection.setText("No se pudo iniciar: " + e.getMessage());
        }
    }

    @Override public void onLocationChanged(Location location) {
        if (server == null) return;
        if (location.isFromMockProvider() || !location.hasAccuracy() || location.getAccuracy() <= 0 || location.getAccuracy() > 100) {
            server.invalidate();
            gps.setText("Posición descartada: simulada o precisión mayor de 100 m.");
            return;
        }
        long stamp = location.getElapsedRealtimeNanos() / 1_000_000;
        long age = SystemClock.elapsedRealtime() - stamp;
        if (age < 0 || age >= 2500) {
            server.invalidate();
            gps.setText("Esperando una posición GPS reciente.");
            return;
        }
        server.publish(new GpsServer.Fix(++seq, location.getLatitude(), location.getLongitude(), location.getAccuracy(), stamp));
        gps.setText(String.format(Locale.getDefault(), "%.6f, %.6f\nPrecisión: %.0f m · posición %d", location.getLatitude(), location.getLongitude(), location.getAccuracy(), seq));
    }

    @Override public void onProviderDisabled(String provider) {
        if (server != null) { server.invalidate(); gps.setText("GPS desactivado · esperando señal"); }
    }

    private String addresses() {
        List<String> found = new ArrayList<>();
        try {
            for (NetworkInterface iface : Collections.list(NetworkInterface.getNetworkInterfaces())) {
                if (!iface.isUp() || iface.isLoopback() || iface.getName().startsWith("tun")) continue;
                for (InetAddress ip : Collections.list(iface.getInetAddresses()))
                    if (ip instanceof Inet4Address && ip.isSiteLocalAddress()) found.add(ip.getHostAddress() + " · " + iface.getName());
            }
        } catch (Exception ignored) { }
        return found.isEmpty() ? "Sin IP local: activa el hotspot." : String.join("\n", found);
    }

    private void stop() {
        GpsServer current = server;
        server = null;
        if (current != null) current.close();
        try { locations.removeUpdates(this); } catch (SecurityException ignored) { }
        ui.removeCallbacks(refresh);
        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        toggle.setText("Iniciar GPS");
        connection.setText("Detenido");
        endpoint.setText("Inicia para obtener dirección y un nuevo código.");
        gps.setText("Sin posición GPS");
    }

    @Override protected void onStop() { stop(); super.onStop(); }
}
