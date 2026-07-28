/// Default implementation of the address-bar cleanup: do nothing.
///
/// Only the web has an address bar to clean, and only the web can receive a URL fragment in the
/// first place, so every other target legitimately no-ops. There is no `dart.library.io` variant
/// beside the web one for that reason — native falls through to this file, which is the correct
/// behaviour rather than a gap.
void clearAuthLinkFromUrl() {}
