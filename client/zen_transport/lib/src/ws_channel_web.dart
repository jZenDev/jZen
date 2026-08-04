// Web WebSocket connect. [headers] is accepted for signature parity across the seam and is
// deliberately ignored: the browser WebSocket API accepts no custom headers at all, and it does
// not need to - it attaches its own cookies to a same-origin handshake automatically, which is
// exactly the session jZen's authenticated socket endpoint asks for. `handshakeHeaders()` on the
// web session client returns an empty map for the same reason, so nothing is being dropped here.
import 'package:web_socket_channel/web_socket_channel.dart';

/// Opens a channel to [uri]; the browser supplies the session cookie itself.
WebSocketChannel connectChannel(Uri uri, Map<String, String> headers) =>
    WebSocketChannel.connect(uri);
