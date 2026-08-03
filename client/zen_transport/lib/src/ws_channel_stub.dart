// Fallback for platforms that are neither dart:io nor a web compiler. Mirrors
// zen_codec_selector_stub.dart and session_client_stub.dart. It connects without headers rather
// than throwing, so a consumer on an exotic platform still gets a socket - it just cannot carry a
// session onto the handshake, which is the same position the web branch is in.
import 'package:web_socket_channel/web_socket_channel.dart';

/// Opens a channel, ignoring [headers] because this platform has no way to send them.
WebSocketChannel connectChannel(Uri uri, Map<String, String> headers) =>
    WebSocketChannel.connect(uri);
