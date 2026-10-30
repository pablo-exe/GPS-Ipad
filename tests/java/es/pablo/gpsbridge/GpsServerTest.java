package es.pablo.gpsbridge;

import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicLong;

public final class GpsServerTest {
    private static void require(boolean value, String message) { if (!value) throw new AssertionError(message); }
    public static void main(String[] args) throws Exception {
        require(GpsServer.authenticated("{\"token\": \"123456\", \"v\":1}", "123456"), "JSON key order");
        require(!GpsServer.authenticated("{\"token\":\"000000\",\"v\":1}", "123456"), "Wrong token rejected");
        AtomicLong clock = new AtomicLong(10_000);
        GpsServer server = new GpsServer(clock::get, status -> {});
        try (server) {
            server.start();
            server.publish(new GpsServer.Fix(1, 40.4168, -3.7038, 5, 10_000));
            try (Socket client = new Socket("127.0.0.1", GpsServer.PORT)) {
                client.setSoTimeout(3000);
                OutputStream out = client.getOutputStream();
                out.write("{\"v\":1,".getBytes(StandardCharsets.UTF_8));
                out.flush();
                out.write(("\"token\":\"" + server.token + "\"}\n").getBytes(StandardCharsets.UTF_8));
                out.flush();
                BufferedReader in = new BufferedReader(new InputStreamReader(client.getInputStream(), StandardCharsets.UTF_8));
                String frame = in.readLine();
                require(frame.contains("\"lat\":40.41680000"), "Real TCP carries coordinates");
                require(frame.contains("\"age_ms\":0"), "Monotonic source age");
                clock.set(12_500);
                do { frame = in.readLine(); } while (!frame.contains("waiting"));
                require(!frame.contains("lat"), "Stale coordinates are not resent");
                server.publish(new GpsServer.Fix(2, 41, -4, 8, 12_500));
                do { frame = in.readLine(); } while (!frame.contains("\"seq\":2"));
                require(frame.contains("41.00000000"), "Fresh GPS recovers");
                server.invalidate();
                do { frame = in.readLine(); } while (!frame.contains("waiting"));
            }
        }
        // Server shutdown releases the port and actively closes a connected client.
        try (GpsServer second = new GpsServer(clock::get, status -> {})) {
            second.start();
            try (Socket client = new Socket("127.0.0.1", GpsServer.PORT)) {
                client.setSoTimeout(3000);
                client.getOutputStream().write("{\"v\":1,\"token\":\"wrong\"}\n".getBytes(StandardCharsets.UTF_8));
                require(client.getInputStream().read() == -1, "Unauthorized client is closed");
            }
        }
        System.out.println("PASS: TCP handshake, auth, freshness, GPS recovery, invalidation and port reuse");
    }
}
