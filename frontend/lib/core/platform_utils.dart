import 'platform_utils_stub.dart'
    if (dart.library.io) 'platform_utils_io.dart' as _impl;

bool get isDesktop => _impl.isDesktop;
