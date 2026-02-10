import 'package:logger/logger.dart';
import 'package:talktime/core/websocket/websocket_manager.dart';
import 'package:talktime/features/chat/data/message_service.dart';

/// Service that manages cross-device message synchronization
/// Initialize this service after WebSocketManager is connected
class DeviceSyncService {
  static final DeviceSyncService _instance = DeviceSyncService._internal();
  factory DeviceSyncService() => _instance;
  DeviceSyncService._internal();

  final Logger _logger = Logger(output: ConsoleOutput());
  final MessageService _messageService = MessageService();
  bool _isInitialized = false;
  bool _hasSyncedOnStartup = false;

  /// Initialize the device sync service
  /// This should be called after WebSocketManager is initialized
  void initialize() {
    if (_isInitialized) return;
    
    _logger.i('Initializing DeviceSyncService');
    
    final wsManager = WebSocketManager();
    
    // Listen for new device connections - request sync from them
    wsManager.onDeviceConnected(_onDeviceConnected);
    
    // Listen for notification that other devices are available
    wsManager.onOtherDevicesAvailable(_onOtherDevicesAvailable);
    
    // Listen for sync requests from other devices
    wsManager.onDeviceSyncRequest(_onDeviceSyncRequest);
    
    // Listen for incoming sync data
    wsManager.onDeviceSyncData(_onDeviceSyncData);
    
    _isInitialized = true;
    _logger.i('DeviceSyncService initialized');

    // Request sync after connection has had time to establish (doesn't rely on OtherDevicesAvailable)
    Future.delayed(const Duration(seconds: 3), () {
      if (!_isInitialized) return;
      _logger.i('Requesting initial sync from other devices');
      requestSyncFromOtherDevices();
    });
  }

  /// Called when the server notifies us that other devices are available
  /// This happens when THIS device connects and there are already other devices
  Future<void> _onOtherDevicesAvailable(OtherDevicesAvailableEvent event) async {
    _logger.i('Server notified: ${event.otherDeviceCount} other device(s) available for sync');
    
    if (_hasSyncedOnStartup) {
      _logger.i('Already synced on startup, skipping');
      return;
    }
    
    if (event.otherDeviceCount > 0) {
      _logger.i('Requesting sync from ${event.otherDeviceCount} other device(s)...');
      _hasSyncedOnStartup = true;
      
      try {
        // Request sync from all other devices
        await WebSocketManager().requestDeviceSync();
        _logger.i('Sync request sent to other devices');
      } catch (e) {
        _logger.e('Failed to request sync: $e');
      }
    }
  }

  /// Called when another device of the same user connects
  void _onDeviceConnected(DeviceConnectedEvent event) {
    _logger.i('New device connected: ${event.deviceId}, total devices: ${event.totalDevices}');
    
    // When a new device connects, we can optionally request sync from it
    // The new device will request sync from us via DeviceSyncRequest
  }

  /// Called when another device requests sync data from us
  Future<void> _onDeviceSyncRequest(DeviceSyncRequest request) async {
    _logger.i('Received sync request from device: ${request.requestingDeviceId}');
    await _messageService.handleDeviceSyncRequest(request);
  }

  /// Called when we receive sync data from another device
  Future<void> _onDeviceSyncData(DeviceSyncChunk chunk) async {
    _logger.i('Received sync chunk ${chunk.chunkIndex}/${chunk.totalChunks} from device: ${chunk.fromDeviceId}');
    await _messageService.handleDeviceSyncData(chunk);
  }

  /// Request sync from all other connected devices
  /// Call this when the app starts or when user wants to manually sync
  Future<void> requestSyncFromOtherDevices({
    String? conversationId,
    int? sinceTimestamp,
  }) async {
    _logger.i('Requesting sync from other devices');
    await WebSocketManager().requestDeviceSync(
      conversationId: conversationId,
      sinceTimestamp: sinceTimestamp,
    );
  }

  /// Request sync for a specific conversation
  Future<void> syncConversation(String conversationId, {int? sinceTimestamp}) async {
    _logger.i('Requesting sync for conversation: $conversationId');
    await WebSocketManager().requestDeviceSync(
      conversationId: conversationId,
      sinceTimestamp: sinceTimestamp,
    );
  }

  /// Dispose the service
  void dispose() {
    if (!_isInitialized) return;
    
    final wsManager = WebSocketManager();
    wsManager.removeDeviceConnectedCallback(_onDeviceConnected);
    wsManager.removeOtherDevicesAvailableCallback(_onOtherDevicesAvailable);
    wsManager.removeDeviceSyncRequestCallback(_onDeviceSyncRequest);
    wsManager.removeDeviceSyncDataCallback(_onDeviceSyncData);
    
    _isInitialized = false;
    _logger.i('DeviceSyncService disposed');
  }
}
