package es.pablo.gpsbridge;

import android.Manifest;
import android.app.Activity;
import android.content.*;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.*;
import android.provider.Settings;
import android.widget.*;
import java.net.*;
import java.util.*;

public final class MainActivity extends Activity {
    private TextView connection, gps, endpoint, battery;
    private Button toggle;
    private final Handler ui = new Handler(Looper.getMainLooper());
    private final Runnable refresh = new Runnable() {
        public void run() { render(); ui.postDelayed(this, 1000); }
    };
    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved);
        ScrollView scroll = new ScrollView(this);
        LinearLayout content = new LinearLayout(this); content.setOrientation(LinearLayout.VERTICAL);
        int space = (int) (24 * getResources().getDisplayMetrics().density);
        content.setPadding(space, space, space, space);
        content.setOnApplyWindowInsetsListener((view, insets) -> {
            view.setPadding(space, space + insets.getSystemWindowInsetTop(), space, space + insets.getSystemWindowInsetBottom()); return insets;
        });
        scroll.addView(content);
        label(content, "Compartir GPS", 28).setAccessibilityHeading(true);
        label(content, "Activa el hotspot y conecta el iPad. Inicia aquí el GPS; después puedes bloquear el Android. La notificación permite detener la sesión.", 17);
        toggle = new Button(this);
        toggle.setOnClickListener(v -> {
            if (GpsService.snapshot().running()) stopService(new Intent(this, GpsService.class)); else requestStart();
        }); content.addView(toggle);
        connection = label(content, "", 20);
        endpoint = label(content, "", 17); endpoint.setTextIsSelectable(true);
        gps = label(content, "", 17); battery = label(content, "", 16);
        Button settings = new Button(this); settings.setText("Permitir GPS continuo con pantalla apagada");
        settings.setOnClickListener(v -> {
            String action = getSystemService(PowerManager.class).isIgnoringBatteryOptimizations(getPackageName())
                ? Settings.ACTION_APPLICATION_DETAILS_SETTINGS : Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS;
            startActivity(new Intent(action, Uri.parse("package:" + getPackageName())));
        });
        content.addView(settings);
        label(content, "Para trayectos con pantalla apagada, configura batería sin restricciones y desactiva el apagado automático del hotspot. No fuerces la detención de la app.", 15);
        setContentView(scroll);
    }
    private TextView label(LinearLayout parent, String text, int size) {
        TextView view = new TextView(this); view.setText(text); view.setTextSize(size);
        int p = (int) (12 * getResources().getDisplayMetrics().density);
        view.setPadding(0, p, 0, p); parent.addView(view); return view;
    }
    private void render() {
        GpsService.Snapshot state = GpsService.snapshot();
        toggle.setText(state.running() ? "Detener GPS" : "Iniciar GPS en segundo plano");
        connection.setText(state.connection());
        endpoint.setText(state.running() ? "Direcciones Android · puerto 8765\n" + addresses() + "\n\nCódigo de sesión: " + state.token() : "Inicia para obtener dirección y código.");
        gps.setText(state.gps());
        boolean exempt = getSystemService(PowerManager.class).isIgnoringBatteryOptimizations(getPackageName());
        battery.setText(exempt ? "Batería: sin optimización de Doze" : "Batería: revisa restricciones para evitar cortes con pantalla apagada");
    }
    private void requestStart() {
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION}, 1); return;
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 2); return;
        }
        startGps();
    }
    private void startGps() {
        try { startForegroundService(new Intent(this, GpsService.class)); }
        catch (RuntimeException e) { connection.setText("No se pudo iniciar. Vuelve a abrir la app: " + e.getMessage()); }
    }
    @Override public void onRequestPermissionsResult(int request, String[] permissions, int[] results) {
        super.onRequestPermissionsResult(request, permissions, results);
        if (request == 1) {
            if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) requestStart();
            else connection.setText("Hace falta ubicación precisa. Actívala en Ajustes → Aplicaciones → GPS Sender → Permisos.");
        } else if (request == 2) startGps();
    }
    private String addresses() {
        List<String> found = new ArrayList<>();
        try {
            for (NetworkInterface iface : Collections.list(NetworkInterface.getNetworkInterfaces())) {
                if (!iface.isUp() || iface.isLoopback() || iface.getName().startsWith("tun")) continue;
                for (InetAddress ip : Collections.list(iface.getInetAddresses()))
                    if (ip instanceof Inet4Address && ip.isSiteLocalAddress()) found.add(ip.getHostAddress() + " · " + iface.getName());
            }
        } catch (SocketException ignored) { }
        return found.isEmpty() ? "Sin IP local: activa el hotspot." : String.join("\n", found);
    }
    @Override protected void onStart() { super.onStart(); refresh.run(); }
    @Override protected void onStop() { ui.removeCallbacks(refresh); super.onStop(); }
}
