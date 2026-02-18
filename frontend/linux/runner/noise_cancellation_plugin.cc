#include "noise_cancellation_plugin.h"

#include <flutter_linux/flutter_linux.h>

namespace {

static FlMethodChannel* g_channel = nullptr;

static void method_call_cb(FlMethodChannel* channel,
                           FlMethodCall* method_call,
                           gpointer user_data) {
  g_autoptr(FlMethodResponse) response = nullptr;
  const gchar* method = fl_method_call_get_name(method_call);

  if (g_strcmp0(method, "pushPcm") == 0) {
    // Stub: accept bytes from Dart (denoised PCM). When pushable WebRTC
    // track exists, feed bytes to ring buffer.
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to send response: %s", error->message);
  }
}

}  // namespace

void register_noise_cancellation_plugin(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) registrar =
      fl_plugin_registry_get_registrar_for_plugin(
          registry, "FlutterWebRTCPlugin");
  if (!registrar) {
    return;
  }

  FlBinaryMessenger* messenger =
      fl_plugin_registrar_get_messenger(registrar);
  if (!messenger) {
    return;
  }

  g_autoptr(FlStandardMethodCodec) codec =
      fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(messenger,
                           "org.radostsladost.talktime/noise_cancellation",
                           FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel, method_call_cb, nullptr, nullptr);

  g_channel = FL_METHOD_CHANNEL(g_object_ref(channel));
}
