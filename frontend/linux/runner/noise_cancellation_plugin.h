#ifndef RUNNER_NOISE_CANCELLATION_PLUGIN_H_
#define RUNNER_NOISE_CANCELLATION_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

// Registers the noise cancellation method channel.
// Channel: org.radostsladost.talktime/noise_cancellation
// Method pushPcm(bytes): stub for now; when pushable WebRTC track exists, bytes feed a ring buffer.
void register_noise_cancellation_plugin(FlPluginRegistry* registry);

#endif  // RUNNER_NOISE_CANCELLATION_PLUGIN_H_
