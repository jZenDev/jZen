import 'backend_network_stub.dart' if (dart.library.io) 'backend_network_io.dart' as platform;

/// Installs the demo's outbound boundary before any repository creates a client.
void installBackendNetwork(String backend) => platform.installBackendNetwork(backend);
