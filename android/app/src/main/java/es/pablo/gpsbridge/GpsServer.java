package es.pablo.gpsbridge;

import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.*;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.Consumer;
import java.util.function.LongSupplier;
import java.util.regex.*;

/** Pull-only v2: one reply per timed request, with no queued GPS history. */
public final class GpsServer implements AutoCloseable {
    public static final int PORT = 8765;
    private static final Pattern REQUEST = Pattern.compile("\\{\\\"v\\\":2,\\\"request_id\\\":([1-9][0-9]{0,17})\\}");
    private final ServerSocket listener;
    private final LongSupplier clock;
    private final Consumer<String> status;
    private final AtomicReference<Socket> active = new AtomicReference<>();
    private volatile Socket authenticating;
    private volatile boolean running = true;
    private volatile Fix latest;
    public final String session = UUID.randomUUID().toString();
    public final String token;

    public record Fix(long seq, double lat, double lon, double accuracy, long elapsedMs) {
        String frame(long now, long request) {
            long age = now - elapsedMs;
            if (age < 0 || age >= 2500) return waiting(request);
            return String.format(Locale.ROOT,
                "{\"v\":2,\"type\":\"fix\",\"request_id\":%d,\"seq\":%d,\"lat\":%.8f,\"lon\":%.8f,\"accuracy\":%.2f,\"age_ms\":%d}\n",
                request, seq, lat, lon, accuracy, age);
        }
    }

    public GpsServer(LongSupplier clock, Consumer<String> status, String token) throws IOException {
        this.clock = clock; this.status = status; this.token = token;
        listener = new ServerSocket();
        listener.setReuseAddress(true);
        listener.bind(new InetSocketAddress(PORT));
    }
    public static String newToken() { return String.format(Locale.ROOT, "%06d", new SecureRandom().nextInt(1_000_000)); }
    public void publish(Fix fix) { latest = fix; }
    public void invalidate() { latest = null; }
    public void start() { new Thread(this::accept, "gps-accept").start(); }

    private void accept() {
        while (running) {
            Socket socket = null;
            try {
                socket = listener.accept(); authenticating = socket;
                socket.setTcpNoDelay(true); socket.setKeepAlive(true);
                if (!authenticated(readLine(socket, 3000), token)) {
                    send(socket, "{\"v\":2,\"type\":\"error\",\"code\":\"auth\"}\n");
                    closeSocket(socket); continue;
                }
                if (!running) { closeSocket(socket); break; }
                // Reconnect replaces the authenticated iPad's old half-open socket.
                closeSocket(active.getAndSet(socket));
                Socket accepted = socket;
                new Thread(() -> serve(accepted), "gps-client").start();
            } catch (IOException e) {
                closeSocket(socket);
                if (running && active.get() == null) status.accept("Esperando reconexión del iPad");
            } finally { authenticating = null; }
        }
    }

    private void serve(Socket socket) {
        try (socket) {
            send(socket, "{\"v\":2,\"type\":\"hello\",\"session\":\"" + session + "\"}\n");
            status.accept("iPad conectado · GPS activo");
            while (running && active.get() == socket) {
                Matcher request = REQUEST.matcher(readLine(socket, 5000).replaceAll("\\s", ""));
                if (!request.matches()) throw new IOException("Petición inválida");
                long id = Long.parseLong(request.group(1));
                Fix fix = latest;
                send(socket, fix == null ? waiting(id) : fix.frame(clock.getAsLong(), id));
            }
        } catch (IOException | NumberFormatException ignored) {
            // The independent listener remains available during a client failure.
        } finally {
            if (active.compareAndSet(socket, null) && running) status.accept("Esperando reconexión del iPad");
        }
    }

    private static String waiting(long request) { return "{\"v\":2,\"type\":\"waiting\",\"request_id\":" + request + "}\n"; }
    private static void send(Socket socket, String text) throws IOException {
        socket.getOutputStream().write(text.getBytes(StandardCharsets.UTF_8)); socket.getOutputStream().flush();
    }
    static boolean authenticated(String hello, String token) {
        String compact = hello.replaceAll("\\s", "");
        return compact.equals("{\"v\":2,\"token\":\"" + token + "\"}")
            || compact.equals("{\"token\":\"" + token + "\",\"v\":2}");
    }
    private static String readLine(Socket socket, int timeoutMs) throws IOException {
        long deadline = System.nanoTime() + timeoutMs * 1_000_000L;
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        for (int n = 0; n < 256; n++) {
            long remaining = (deadline - System.nanoTime()) / 1_000_000;
            if (remaining <= 0) throw new SocketTimeoutException();
            socket.setSoTimeout((int) Math.max(1, remaining));
            int b = socket.getInputStream().read();
            if (b == -1) throw new EOFException();
            if (b == '\n') return new String(bytes.toByteArray(), StandardCharsets.UTF_8);
            bytes.write(b);
        }
        throw new IOException("Trama demasiado grande");
    }
    private static void closeSocket(Socket socket) { if (socket != null) try { socket.close(); } catch (IOException ignored) { } }
    @Override public void close() {
        running = false;
        try { listener.close(); } catch (IOException ignored) { }
        closeSocket(authenticating); closeSocket(active.getAndSet(null)); latest = null;
    }
}
