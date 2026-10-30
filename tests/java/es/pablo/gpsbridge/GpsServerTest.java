package es.pablo.gpsbridge;

import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicLong;

public final class GpsServerTest {
    static void require(boolean value, String message) { if (!value) throw new AssertionError(message); }
    static final class Client implements AutoCloseable {
        final Socket socket = new Socket("127.0.0.1", GpsServer.PORT);
        final BufferedReader input = new BufferedReader(new InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8));
        Client(String token) throws IOException {
            socket.setSoTimeout(2000);
            write("{\"v\":2,"); write("\"token\":\"" + token + "\"}\n");
        }
        void write(String text) throws IOException { socket.getOutputStream().write(text.getBytes(StandardCharsets.UTF_8)); socket.getOutputStream().flush(); }
        String sample(long id) throws IOException { write("{\"v\":2,\"request_id\":" + id + "}\n"); return input.readLine(); }
        public void close() throws IOException { socket.close(); }
    }
    public static void main(String[] args) throws Exception {
        require(GpsServer.authenticated("{\"token\": \"123456\", \"v\":2}", "123456"), "Key order");
        require(!GpsServer.authenticated("{\"v\":1,\"token\":\"123456\"}", "123456"), "No legacy protocol");
        AtomicLong clock = new AtomicLong(10_000);
        String token = GpsServer.newToken();
        try (GpsServer server = new GpsServer(clock::get, s -> {}, token)) {
            server.start(); server.publish(new GpsServer.Fix(1, 40.4168, -3.7038, 5, 10_000));
            try (Client first = new Client(token)) {
                require(first.input.readLine().contains(server.session), "Explicit session handshake");
                first.socket.setSoTimeout(150);
                try { first.input.readLine(); throw new AssertionError("Unrequested GPS data"); } catch (SocketTimeoutException expected) { }
                first.socket.setSoTimeout(2000);
                String frame = first.sample(1);
                require(frame.contains("\"lat\":40.41680000") && frame.contains("\"request_id\":1"), "Matched real TCP reply");
                clock.set(12_500);
                require(first.sample(2).contains("waiting"), "Stale position withheld");
                server.publish(new GpsServer.Fix(2, 41, -4, 8, 12_500));
                require(first.sample(3).contains("\"seq\":2"), "GPS recovery");
                try (Client bad = new Client("wrong")) {
                    require(bad.input.readLine().contains("auth"), "Wrong code is explicit");
                    require(bad.input.readLine() == null, "Unauthorized socket closed");
                }
                require(first.sample(4).contains("\"seq\":2"), "Wrong code cannot evict active client");
                try (Client second = new Client(token)) {
                    require(second.input.readLine().contains("hello"), "Reconnect authenticated");
                    require(first.input.readLine() == null, "Half-open old socket displaced immediately");
                    require(second.sample(1).contains("\"request_id\":1"), "New connection can reset request counter");
                    server.invalidate(); require(second.sample(2).contains("waiting"), "Provider loss invalidates latest");
                    server.publish(new GpsServer.Fix(3, 1, 2, 5, 13_000));
                    require(second.sample(3).contains("waiting"), "Future source timestamp rejected");
                }
            }
        }
        try (GpsServer next = new GpsServer(clock::get, s -> {}, token)) {
            next.start();
            try (Client idle = new Client(token)) {
                require(idle.input.readLine().contains("hello"), "Port reusable after shutdown");
                idle.socket.setSoTimeout(6500);
                require(idle.input.readLine() == null, "Idle client timed out without blocking listener");
            }
        }
        System.out.println("PASS: pull-only TCP, fragmented auth, correlated requests, GNSS expiry/recovery, client takeover, wrong-code isolation, idle timeout and port reuse");
    }
}
