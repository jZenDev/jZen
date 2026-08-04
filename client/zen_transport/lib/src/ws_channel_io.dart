// Native WebSocket connect (dart:io). This is the branch that can carry a session onto the
// handshake: IOWebSocketChannel exposes the upgrade request's headers, so the cookie jar's
// `Cookie:` header reaches the server's authenticated endpoint. Without it a native client
// upgrades anonymously and jZen's socket closes on it, while the web build - where the browser
// attaches the cookie itself - works. That asymmetry is precisely why this is a compile-time seam
// and not a runtime check.
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Opens a channel to [uri], sending [headers] on the HTTP upgrade request.
WebSocketChannel connectChannel(Uri uri, Map<String, String> headers) =>
    IOWebSocketChannel.connect(uri, headers: headers.isEmpty ? null : headers);
