package es.pablo.gpsbridge;

import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.Locale;
import java.util.function.Consumer;
import java.util.function.LongSupplier;

/** One authenticated LAN client. Only the newest fix is retained, never a route/history. */
public final class GpsServer implements AutoCloseable {
    public static final int PORT = 8765;
    private final ServerSocket listener;
    private final LongSupplier clock;
    private final Consumer<String> status;
    private volatile Socket client;
    private volatile boolean running = true;
    private volatile Fix latest;
    public final String token = String.format(Locale.ROOT, "%06d", new SecureRandom().nextInt(1_000_000));

    public record Fix(long seq, double lat, double lon, double accuracy, long elapsedMs) {
        String frame(long now) {
            long age = Math.max(0, now - elapsedMs);
            if (age >= 2500) return "{\"v\":1,\"type\":\"waiting\"}\n";
            return String.format(Locale.ROOT,
                "{\"v\":1,\"type\":\"fix\",\"seq\":%d,\"lat\":%.8f,\"lon\":%.8f,\"accuracy\":%.2f,\"age_ms\":%d}\n",
                seq, lat, lon, accuracy, age);
        }
    }

    public GpsServer(LongSupplier clock, Consumer<String> status) throws IOException {
        this.clock = clock;
        this.status = status;
        listener = new ServerSocket();
        listener.setReuseAddress(true);
        listener.bind(new InetSocketAddress(PORT));
    }

    public void publish(Fix fix) { latest = fix; }
    public void invalidate() { latest = null; }
    public void start() { new Thread(this::serve, "gps-lan").start(); }

    private void serve() {
        while (running) {
            try (Socket socket = listener.accept()) {
                client = socket;
                socket.setTcpNoDelay(true);
                socket.setSoTimeout(5000);
                String hello = readLine(socket.getInputStream());
                if (!authenticated(hello, token)) {
                    status.accept("Código incorrecto. Revisa el código en el iPad.");
                    continue;
                }
                status.accept("iPad conectado · enviando GPS");
                OutputStream out = socket.getOutputStream();
                while (running) {
                    Fix fix = latest;
                    String frame = fix == null ? "{\"v\":1,\"type\":\"waiting\"}\n" : fix.frame(clock.getAsLong());
                    out.write(frame.getBytes(StandardCharsets.UTF_8));
                    out.flush();
                    Thread.sleep(500);
                }
            } catch (IOException e) {
                if (running) status.accept("Sin cliente · reconecta desde el iPad");
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                break;
            } finally {
                client = null;
            }
        }
    }

    static boolean authenticated(String hello, String token) {
        // A deliberately tiny protocol: exactly version and token, no extra fields.
        String compact = hello.replaceAll("\\s", "");
        return compact.equals("{\"v\":1,\"token\":\"" + token + "\"}")
            || compact.equals("{\"token\":\"" + token + "\",\"v\":1}");
    }

    private static String readLine(InputStream in) throws IOException {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        for (int n = 0; n < 256; n++) {
            int b = in.read();
            if (b == -1) throw new EOFException();
            if (b == '\n') return new String(bytes.toByteArray(), StandardCharsets.UTF_8);
            bytes.write(b);
        }
        throw new IOException("Handshake demasiado grande");
    }

    @Override public void close() {
        running = false;
        try { listener.close(); } catch (IOException ignored) { }
        Socket socket = client;
        if (socket != null) try { socket.close(); } catch (IOException ignored) { }
        latest = null;
    }
}
