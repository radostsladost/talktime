// Conditional export: stub on web, real implementation on desktop (dart.library.io).
export 'desktop_noise_cancellation_pipeline_stub.dart'
    if (dart.library.io) 'desktop_noise_cancellation_pipeline_io.dart';
