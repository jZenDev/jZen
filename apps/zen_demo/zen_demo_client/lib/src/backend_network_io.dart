import 'dart:io';

void installBackendNetwork(String backend) {
  HttpOverrides.global = BackendNetwork(Uri.parse(backend));
}

/// The demo reaches its configured backend only. This covers dart:io HTTP,
/// package:http and WebSocket upgrades, including redirects and DNS rebinding.
/// Native plugins and the Flutter engine are audited separately: HttpOverrides
/// does not intercept their sockets, raw Dart sockets, or other isolates.
class BackendNetwork extends HttpOverrides {
  BackendNetwork(this.backend, {this.lookup = InternetAddress.lookup}) {
    if (!{'http', 'https'}.contains(backend.scheme) ||
        backend.host.isEmpty ||
        backend.userInfo.isNotEmpty) {
      throw ArgumentError.value(
        backend,
        'backend',
        'Expected an HTTP(S) backend without user info',
      );
    }
    _checkHost(backend.host);
  }

  final Uri backend;
  final Future<List<InternetAddress>> Function(String) lookup;

  @override
  HttpClient createHttpClient(SecurityContext? context) => super.createHttpClient(context)
    // An environment proxy could otherwise connect to another local device or
    // resolve the destination itself, bypassing the address check below.
    ..findProxy = ((_) => 'DIRECT')
    ..connectionFactory = ((uri, host, port) => connect(uri, host, port, context: context));

  Future<ConnectionTask<Socket>> connect(
    Uri uri,
    String? proxyHost,
    int? proxyPort, {
    SecurityContext? context,
  }) async {
    if (uri.scheme != backend.scheme ||
        uri.host != backend.host ||
        uri.port != backend.port ||
        uri.userInfo.isNotEmpty ||
        proxyHost != null ||
        proxyPort != null) {
      throw const SocketException('Demo network policy: only the configured backend is allowed');
    }
    _checkHost(uri.host);
    // localhost is this computer, even if a resolver or hosts file says otherwise.
    // Public names are absolute so the OS cannot append a local search domain.
    final literal = InternetAddress.tryParse(uri.host);
    final addresses = uri.host == 'localhost'
        ? [InternetAddress.loopbackIPv4, InternetAddress.loopbackIPv6]
        : literal != null
        ? [literal]
        : await lookup(uri.host.endsWith('.') ? uri.host : '${uri.host}.');
    final explicitLoopback = uri.host == 'localhost' || literal != null;
    if (addresses.isEmpty ||
        addresses.any((a) => !isBackendAddress(a) || (!explicitLoopback && _isLoopback(a)))) {
      throw const SocketException(
        'Demo network policy: local, multicast or reserved address refused',
      );
    }

    // Connect to the checked numeric address, never resolve the name a second
    // time. A custom connection factory also owns TLS: upgrade using the original
    // hostname, preserving certificate verification and SNI.
    ConnectionTask<Socket>? pending;
    Socket? active;
    var cancelled = false;
    Future<Socket> open() async {
      SocketException? lastError;
      for (final address in addresses) {
        if (cancelled) throw const SocketException('Connection cancelled');
        try {
          pending = await Socket.startConnect(address, uri.port);
          if (cancelled) pending!.cancel();
          active = await pending!.socket;
          if (uri.scheme == 'https') {
            return await SecureSocket.secure(active!, host: uri.host, context: context);
          }
          return active!;
        } on SocketException catch (error) {
          lastError = error;
        }
      }
      throw lastError!;
    }

    return ConnectionTask.fromSocket(open(), () {
      cancelled = true;
      pending?.cancel();
      active?.destroy();
    });
  }

  static void _checkHost(String host) {
    // Refuse names that could cause mDNS, search-domain or interface-scoped
    // resolution BEFORE asking the resolver anything about them.
    if (host.contains('%')) {
      throw const SocketException('Demo network policy: interface-scoped address refused');
    }
    final name = host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    final literal = InternetAddress.tryParse(host);
    if (literal != null) {
      if (isBackendAddress(literal)) return;
    } else if (name == 'localhost' ||
        (name.contains('.') &&
            !name.endsWith('.local') &&
            !name.endsWith('.localhost') &&
            !name.endsWith('.home.arpa') &&
            !host.contains('%'))) {
      return;
    }
    throw const SocketException('Demo network policy: local discovery names and addresses refused');
  }

  static bool _isLoopback(InternetAddress address) {
    final b = address.rawAddress;
    return address.isLoopback ||
        (b.length == 4 && b[0] == 127) ||
        (b.length == 16 &&
            b.take(10).every((v) => v == 0) &&
            b[10] == 255 &&
            b[11] == 255 &&
            b[12] == 127);
  }

  /// Loopback for same-machine development, or ordinary public unicast.
  static bool isBackendAddress(InternetAddress address) {
    if (address.type != InternetAddressType.IPv4 && address.type != InternetAddressType.IPv6) {
      return false;
    }
    final b = address.rawAddress;
    if (b.length == 16) {
      // IPv4-mapped IPv6 must obey the IPv4 rules, including 127/8.
      if (b.take(10).every((v) => v == 0) && b[10] == 255 && b[11] == 255) {
        return isBackendAddress(InternetAddress.fromRawAddress(b.sublist(12)));
      }
      if (address.isLoopback) return true;
      // IPv6 global unicast only; excludes ULA, link-local, multicast,
      // unspecified, NAT64 and other translation ranges. Exclude 6to4 and
      // protocol-assignment/documentation space within 2000::/3 as well.
      return b[0] & 0xe0 == 0x20 &&
          !(b[0] == 0x20 && b[1] == 0x02) &&
          !(b[0] == 0x20 && b[1] == 0x01 && b[2] < 2) &&
          !(b[0] == 0x20 && b[1] == 0x01 && b[2] == 0x0d && b[3] == 0xb8) &&
          !(b[0] == 0x3f && b[1] == 0xff && b[2] < 0x10);
    }
    if (b[0] == 127) return true;
    return b[0] != 0 &&
        b[0] != 10 &&
        !(b[0] == 100 && b[1] >= 64 && b[1] <= 127) &&
        !(b[0] == 169 && b[1] == 254) &&
        !(b[0] == 172 && b[1] >= 16 && b[1] <= 31) &&
        !(b[0] == 192 &&
            (b[1] == 168 ||
                b[1] == 0 ||
                (b[1] == 2 && b[2] == 0) || // TEST-NET-1 documentation addresses.
                (b[1] == 88 && b[2] == 99))) &&
        !(b[0] == 198 && (b[1] == 18 || b[1] == 19 || (b[1] == 51 && b[2] == 100))) &&
        !(b[0] == 203 && b[1] == 0 && b[2] == 113) &&
        b[0] < 224;
  }
}
