#ifndef RUNNER_NOISE_CANCELLATION_PLUGIN_H_
#define RUNNER_NOISE_CANCELLATION_PLUGIN_H_

#include <flutter/plugin_registry.h>

// Registers the noise cancellation method channel.
// Channel: org.radostsladost.talktime/noise_cancellation
// Method pushPcm(bytes): stub for now; when pushable WebRTC track exists, bytes feed a ring buffer.
void RegisterNoiseCancellationPlugin(flutter::PluginRegistry* registry);

#endif  // RUNNER_NOISE_CANCELLATION_PLUGIN_H_
