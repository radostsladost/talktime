#include "noise_cancellation_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>

namespace {

// Keeps the method channel alive for the app lifetime.
static std::unique_ptr<
    flutter::MethodChannel<flutter::EncodableValue>>
    g_noise_cancellation_channel;

void RegisterNoiseCancellationChannel(flutter::PluginRegistry* registry) {
  // Use an existing plugin's registrar to get the binary messenger.
  flutter::PluginRegistrarWindows* registrar =
      registry->GetRegistrarForPlugin("FlutterWebRTCPlugin");
  if (!registrar) {
    return;
  }
  g_noise_cancellation_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(),
          "org.radostsladost.talktime/noise_cancellation",
          &flutter::StandardMethodCodec::GetInstance());

  g_noise_cancellation_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<
             flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "pushPcm") {
          // Stub: accept bytes from Dart (denoised PCM). When pushable
          // WebRTC track exists, feed bytes to ring buffer.
          result->Success(flutter::EncodableValue());
        } else {
          result->NotImplemented();
        }
      });
}

}  // namespace

void RegisterNoiseCancellationPlugin(flutter::PluginRegistry* registry) {
  RegisterNoiseCancellationChannel(registry);
}
