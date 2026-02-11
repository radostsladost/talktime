using System.Collections.Concurrent;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using TalkTime.Core.DTOs;
using TalkTime.Core.Entities;
using TalkTime.Core.Enums;
using TalkTime.Core.Interfaces;

namespace TalkTime.Api.Hubs;

/// <summary>
/// SignalR Hub for real-time messaging and WebRTC signaling
/// </summary>
[Authorize]
public class TalkTimeHub : Hub
{
    private readonly IUserRepository _userRepository;
    private readonly IConversationRepository _conversationRepository;
    private readonly IMessageRepository _messageRepository;
    private readonly INotificationsService _notificationsService;
    private readonly ILogger<TalkTimeHub> _logger;

    // Track connected users: userId -> Set of connectionIds (multiple devices per user)
    private static readonly ConcurrentDictionary<string, ConcurrentDictionary<string, DeviceInfo>> ConnectedUsers = new();

    // Track active calls: callId -> CallInfo
    private static readonly ConcurrentDictionary<string, CallInfo> ActiveCalls = new();

    // Track conference rooms: roomId -> RoomState
    private static readonly ConcurrentDictionary<string, RoomState> ConferenceRooms = new();

    public TalkTimeHub(
        IUserRepository userRepository,
        IConversationRepository conversationRepository,
        IMessageRepository messageRepository,
        INotificationsService notificationsService,
        ILogger<TalkTimeHub> logger)
    {
        _userRepository = userRepository;
        _conversationRepository = conversationRepository;
        _messageRepository = messageRepository;
        _notificationsService = notificationsService;
        _logger = logger;
    }

    public override async Task OnConnectedAsync()
    {
        var userId = GetUserId();
        if (string.IsNullOrEmpty(userId))
        {
            Context.Abort();
            return;
        }

        // Generate a device ID for this connection
        var deviceId = Context.GetHttpContext()?.Request.Query["deviceId"].FirstOrDefault() 
            ?? Context.ConnectionId;
        
        // Track this device connection
        var userDevices = ConnectedUsers.GetOrAdd(userId, _ => new ConcurrentDictionary<string, DeviceInfo>());
        var deviceInfo = new DeviceInfo(Context.ConnectionId, deviceId, DateTime.UtcNow);
        userDevices[Context.ConnectionId] = deviceInfo;

        // If user has other devices connected, notify them about new device
        var otherDevices = userDevices.Values
            .Where(d => d.ConnectionId != Context.ConnectionId)
            .ToList();
        
        if (otherDevices.Any())
        {
            var deviceConnectedEvent = new DeviceConnectedEvent(
                userId,
                deviceId,
                userDevices.Count
            );
            
            // Notify other devices of the same user
            foreach (var otherDevice in otherDevices)
            {
                await Clients.Client(otherDevice.ConnectionId)
                    .SendAsync("DeviceConnected", deviceConnectedEvent);
            }
            
            // Also notify the NEW device that there are other devices it can sync from
            await Clients.Caller.SendAsync("OtherDevicesAvailable", new
            {
                otherDeviceCount = otherDevices.Count,
                totalDevices = userDevices.Count,
                otherDeviceIds = otherDevices.Select(d => d.DeviceId).ToList()
            });
            
            _logger.LogInformation(
                "User {UserId} connected new device {DeviceId}. Total devices: {TotalDevices}. Notified {OtherCount} other devices.",
                userId, deviceId, userDevices.Count, otherDevices.Count);
        }
        else
        {
            _logger.LogInformation(
                "User {UserId} connected device {DeviceId}. This is the only device.",
                userId, deviceId);
        }

        // Update user online status
        await _userRepository.SetOnlineStatusAsync(userId, true);

        // Join user to all their conversation groups
        var conversations = await _conversationRepository.GetUserConversationsAsync(userId);
        foreach (var conversation in conversations)
        {
            await Groups.AddToGroupAsync(Context.ConnectionId, $"conversation_{conversation.Id}");

            // Notify friends/contacts that user is online
            await Clients.OthersInGroup($"conversation_{conversation.Id}").SendAsync("UserOnline", new { userId });

            if (conversation.Participants != null)
            {
                foreach (var participant in conversation.Participants)
                {
                    if (participant.UserId != userId && participant.User.IsOnline)
                    {
                        await Clients.Caller.SendAsync("UserOnline", new { participant.UserId });
                    }
                }
            }
        }

        // Send pending (unread) messages to the user; read state is per-user so others still see them as pending
        var pendingMessages = await _messageRepository.GetPendingMessagesForUserAsync(userId);
        foreach (var message in pendingMessages)
        {
            var messageDto = new MessageDto(
                message.Id,
                message.ConversationId,
                new UserDto(message.Sender.Id, message.Sender.Username, message.Sender.AvatarUrl, message.Sender.Description, message.Sender.IsOnline, message.Sender.LastSeenAt),
                message.EncryptedContent,
                message.Type.ToString().ToLower(),
                message.SentAt.ToString("o"),
                message.MediaUrl,
                message.ThumbnailUrl,
                null
            );
            await Clients.Caller.SendAsync("ReceiveMessage", messageDto);

            // Mark as delivered for this user only
            await _messageRepository.MarkAsDeliveredAsync(message.Id, userId);
        }

        _logger.LogInformation("User {UserId} connected with connection {ConnectionId}, device {DeviceId}", 
            userId, Context.ConnectionId, deviceId);

        await base.OnConnectedAsync();
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        var userId = GetUserId();
        if (!string.IsNullOrEmpty(userId))
        {
            // Remove this specific device connection
            if (ConnectedUsers.TryGetValue(userId, out var userDevices))
            {
                userDevices.TryRemove(Context.ConnectionId, out var removedDevice);
                
                // If user has no more devices connected, set offline
                if (userDevices.IsEmpty)
                {
                    ConnectedUsers.TryRemove(userId, out _);
                    
                    // Update user online status
                    await _userRepository.SetOnlineStatusAsync(userId, false);
                    
                    // Notify others that user is offline
                    await Clients.Others.SendAsync("UserOffline", new { userId, lastSeenAt = DateTime.UtcNow.ToString("o") });
                }
                else
                {
                    // Notify other devices that this device disconnected
                    var deviceDisconnectedEvent = new
                    {
                        UserId = userId,
                        DeviceId = removedDevice?.DeviceId ?? Context.ConnectionId,
                        TotalDevices = userDevices.Count
                    };
                    
                    foreach (var otherDevice in userDevices.Values)
                    {
                        await Clients.Client(otherDevice.ConnectionId)
                            .SendAsync("DeviceDisconnected", deviceDisconnectedEvent);
                    }
                }
            }

            // Leave any active calls
            await LeaveAllCalls(userId);

            _logger.LogInformation("User {UserId} disconnected (connection {ConnectionId})", userId, Context.ConnectionId);
        }

        await base.OnDisconnectedAsync(exception);
    }

    #region Messaging

    /// <summary>
    /// Join a conversation group to receive real-time messages
    /// </summary>
    public async Task JoinConversation(string conversationId)
    {
        var userId = GetUserId();
        if (string.IsNullOrEmpty(userId)) return;

        // Verify user is a participant
        if (!await _conversationRepository.IsParticipantAsync(conversationId, userId))
        {
            await Clients.Caller.SendAsync("Error", new { message = "Not a participant of this conversation" });
            return;
        }

        await Groups.AddToGroupAsync(Context.ConnectionId, $"conversation_{conversationId}");
        await Clients.OthersInGroup($"conversation_{conversationId}").SendAsync("UserOnline", new { userId });
        _logger.LogInformation("User {UserId} joined conversation {ConversationId}", userId, conversationId);

        var conversation = (await _conversationRepository.GetUserConversationsAsync(userId)).FirstOrDefault(i => i.Id == conversationId);
        if (conversation?.Participants != null)
        {
            foreach (var participant in conversation.Participants)
            {
                if (participant.UserId != userId && participant.User.IsOnline)
                {
                    await Clients.Caller.SendAsync("UserOnline", new { participant.UserId });
                }
            }
        }
    }

    /// <summary>
    /// Leave a conversation group
    /// </summary>
    public async Task LeaveConversation(string conversationId)
    {
        await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"conversation_{conversationId}");
        _logger.LogInformation("Connection {ConnectionId} left conversation {ConversationId}", Context.ConnectionId, conversationId);
    }

    /// <summary>
    /// Send typing indicator to conversation participants
    /// </summary>
    public async Task SendTypingIndicator(string conversationId, bool isTyping)
    {
        var userId = GetUserId();
        if (string.IsNullOrEmpty(userId)) return;

        try
        {
            await Clients.OthersInGroup($"conversation_{conversationId}")
                .SendAsync("TypingIndicator", new { conversationId, userId, isTyping });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send typing indicator to conversation {ConversationId}", conversationId);
        }
    }

    /// <summary>
    /// Acknowledge message receipt (for delivery confirmation)
    /// </summary>
    public async Task AcknowledgeMessage(string messageId)
    {
        var userId = GetUserId();
        if (string.IsNullOrEmpty(userId)) return;

        await _messageRepository.MarkAsDeliveredAsync(messageId, userId);

        _logger.LogInformation("User {UserId} acknowledged message {MessageId}", userId, messageId);
    }

    #endregion

    #region Device Sync

    /// <summary>
    /// Request sync from other devices of the same user
    /// Other devices will receive DeviceSyncRequest and should respond with SendDeviceSyncData
    /// </summary>
    public async Task RequestDeviceSync(string conversationId, long sinceTimestamp, int chunkSize = 100)
    {
        var userId = GetUserId();
        if (string.IsNullOrEmpty(userId)) return;

        if (!ConnectedUsers.TryGetValue(userId, out var userDevices)) return;

        // Get this device's ID
        var thisDeviceId = userDevices.Values
            .FirstOrDefault(d => d.ConnectionId == Context.ConnectionId)?.DeviceId 
            ?? Context.ConnectionId;

        // Convert empty string to null for conversationId, 0 to null for sinceTimestamp
        var actualConversationId = string.IsNullOrEmpty(conversationId) ? null : conversationId;
        var actualSinceTimestamp = sinceTimestamp == 0 ? (long?)null : sinceTimestamp;

        var syncRequest = new DeviceSyncRequest(
            thisDeviceId,
            actualConversationId,
            actualSinceTimestamp,
            chunkSize
        );

        // Send request to all other devices of this user
        foreach (var device in userDevices.Values.Where(d => d.ConnectionId != Context.ConnectionId))
        {
            await Clients.Client(device.ConnectionId).SendAsync("DeviceSyncRequest", syncRequest);
        }

        _logger.LogInformation(
            "User {UserId} device {DeviceId} requested sync from {OtherDeviceCount} other devices",
            userId, thisDeviceId, userDevices.Count - 1);
    }

    /// <summary>
    /// Send message sync data to another device
    /// Called in response to DeviceSyncRequest
    /// </summary>
    public async Task SendDeviceSyncData(string toDeviceId, string conversationId, List<SyncMessageDto> messages, int chunkIndex, int totalChunks, bool isLastChunk)
    {
        var userId = GetUserId();
        if (string.IsNullOrEmpty(userId)) return;

        if (!ConnectedUsers.TryGetValue(userId, out var userDevices)) return;

        // Get this device's ID
        var thisDeviceId = userDevices.Values
            .FirstOrDefault(d => d.ConnectionId == Context.ConnectionId)?.DeviceId 
            ?? Context.ConnectionId;

        // Find target device
        var targetDevice = userDevices.Values.FirstOrDefault(d => d.DeviceId == toDeviceId);
        if (targetDevice == null)
        {
            _logger.LogWarning(
                "User {UserId} device {DeviceId} tried to send sync data to unknown device {ToDeviceId}",
                userId, thisDeviceId, toDeviceId);
            return;
        }

        // Convert empty string to null for conversationId
        var actualConversationId = string.IsNullOrEmpty(conversationId) ? null : conversationId;

        var syncChunk = new DeviceSyncChunk(
            thisDeviceId,
            toDeviceId,
            actualConversationId,
            messages,
            chunkIndex,
            totalChunks,
            isLastChunk
        );

        await Clients.Client(targetDevice.ConnectionId).SendAsync("DeviceSyncData", syncChunk);

        _logger.LogInformation(
            "User {UserId} device {DeviceId} sent sync chunk {ChunkIndex}/{TotalChunks} ({MessageCount} messages) to device {ToDeviceId}",
            userId, thisDeviceId, chunkIndex, totalChunks, messages.Count, toDeviceId);
    }

    /// <summary>
    /// Get list of connected devices for current user
    /// </summary>
    public async Task GetConnectedDevices()
    {
        var userId = GetUserId();
        if (string.IsNullOrEmpty(userId)) return;

        if (!ConnectedUsers.TryGetValue(userId, out var userDevices))
        {
            await Clients.Caller.SendAsync("ConnectedDevices", new { devices = new List<object>() });
            return;
        }

        var thisConnectionId = Context.ConnectionId;
        var devices = userDevices.Values.Select(d => new
        {
            deviceId = d.DeviceId,
            connectedAt = d.ConnectedAt.ToString("o"),
            isCurrentDevice = d.ConnectionId == thisConnectionId
        }).ToList();

        await Clients.Caller.SendAsync("ConnectedDevices", new { devices });
    }

    #endregion

    #region WebRTC Signaling - Conference Rooms

    /// <summary>
    /// Create a new conference room
    /// </summary>
    /// <param name="roomName">ConversationId</param>
    public async Task CreateRoom(string roomName)
    {
        var userId = GetUserId();
        if (string.IsNullOrEmpty(userId)) return;

        var user = await _userRepository.GetByIdAsync(userId);
        if (user == null) return;

        if (roomName == null || !await _conversationRepository.IsParticipantAsync(roomName, userId))
        {
            await Clients.Caller.SendAsync("Error", new { message = "Not a participant of this conversation" });
            return;
        }
        var existRoom = ConferenceRooms.FirstOrDefault(x => x.Value.Name == roomName);
        if (existRoom.Value != null)
        {
            await JoinRoom(existRoom.Value.RoomId);
            return;
        }

        var roomId = roomName;
        var roomState = new RoomState
        {
            RoomId = roomName,
            Name = roomName,
            CreatedBy = userId,
            CreatedAt = DateTime.UtcNow
        };

        ConferenceRooms[roomId] = roomState;

        // Join the creator to the room
        await JoinRoom(roomId);

        await Clients.Caller.SendAsync("RoomCreated", new RoomInfo(
            roomId,
            roomName,
            new List<UserDto> {
                new UserDto(user.Id, user.Username, user.AvatarUrl, user.Description, user.IsOnline, user.LastSeenAt),
            },
            userId,
            roomState.CreatedAt
        ));

        _logger.LogInformation("Room {RoomId} created by {UserId}", roomId, userId);
    }

    /// <summary>
    /// Join an existing conference room
    /// </summary>
    public async Task JoinRoom(string roomId)
    {
        var userId = GetUserId();
        if (string.IsNullOrEmpty(userId)) return;

        if (!ConferenceRooms.TryGetValue(roomId, out var roomState))
        {
            await Clients.Caller.SendAsync("Error", new { message = "Room not found" });
            return;
        }

        if (!await _conversationRepository.IsParticipantAsync(roomId, userId))
        {
            await Clients.Caller.SendAsync("Error", new { message = "Not a participant of this conversation" });
            return;
        }

        if (roomState.Participants.ContainsKey(userId))
        {
            return;
        }

        var user = await _userRepository.GetByIdAsync(userId);
        if (user == null) return;

        var userDto = new UserDto(user.Id, user.Username, user.AvatarUrl, user.Description, user.IsOnline, user.LastSeenAt);

        // Add user to room
        roomState.Participants[userId] = userDto;

        // Join SignalR group for the room
        await Groups.AddToGroupAsync(Context.ConnectionId, $"room_{roomId}");

        // Notify existing participants
        await Clients.OthersInGroup($"room_{roomId}").SendAsync("ParticipantJoined", new RoomParticipantUpdate(
            roomId,
            userDto,
            "joined"
        ));

        await Clients.Group($"conversation_{roomId}").SendAsync("ParticipantJoined", new RoomParticipantUpdate(
            roomId,
            userDto,
            "joined"
        ));

        // Send current participants to the new user
        var participants = roomState.Participants.Values.ToList();
        await Clients.Caller.SendAsync("RoomJoined", new RoomInfo(
            roomId,
            roomState.Name,
            participants,
            roomState.CreatedBy,
            roomState.CreatedAt
        ));

        // Send existing participants to the new user ONLY (not to everyone)
        foreach (var c in roomState.Participants.ToArray())
        {
            if (c.Value == userDto)
                continue;

            // Only notify the new user about existing participants
            await Clients.Caller.SendAsync("ParticipantJoined", new RoomParticipantUpdate(
                roomId,
                c.Value,
                "joined"
            ));
        }

        _logger.LogInformation("User {UserId} joined room {RoomId}", userId, roomId);

        if (roomState.Participants.Count == 1)
        {
            // CALL TO OTHERS
            var conversations = await _conversationRepository.GetByIdWithParticipantsAsync(roomId);
            foreach (var participant in conversations?.Participants ?? Array.Empty<ConversationParticipant>())
            {
                if (participant.UserId != userId)
                {
                    // Send SignalR notification to online users
                    if (IsUserConnected(participant.UserId))
                    {
                        await Clients.User(participant.UserId).SendAsync("CallInitiated", new RoomParticipantUpdate(
                            roomId,
                            userDto,
                            "joined"
                        ));
                    }
                    // else
                    {
                        // Send push notification to offline users
                        try
                        {
                            var notificationData = System.Text.Json.JsonSerializer.Serialize(new
                            {
                                type = "call",
                                conversationId = roomId,
                                callerId = userId,
                                callerUsername = user.Username
                            });

                            await _notificationsService.SendNotificationAsync(
                                participant.UserId,
                                user.Username ?? "Incoming call",
                                conversations.Type == ConversationType.Direct ? "Calling you" : "Calling in group",
                                user.AvatarUrl,
                                notificationData
                            );
                        }
                        catch (Exception ex)
                        {
                            _logger.LogError(ex, "Failed to send push notification for call to user {UserId}", participant.UserId);
                        }

                        try
                        {
                            await _notificationsService.SendCallNotificationAsync(
                                participant.UserId,
                                user.Username ?? "Incoming call",
                                roomId);
                        }
                        catch (Exception ex)
                        {
                            _logger.LogError(ex, "Failed to send push notification for call (callKit) to user {UserId}", participant.UserId);
                        }
                    }
                }
            }
        }
    }

    /// <summary>
    /// Leave a conference room
    /// </summary>
    public async Task LeaveRoom(string roomId, string reason)
    {
        var userId = GetUserId();
        if (string.IsNullOrEmpty(userId)) return;

        await LeaveRoomInternal(userId, roomId, reason);
    }

    /// <summary>
    /// Get current participants in a conference room
    /// </summary>
    public async Task GetRoomParticipants(string roomId)
    {
        var userId = GetUserId();
        if (string.IsNullOrEmpty(userId)) return;

        // Verify user is a participant of the conversation
        if (!await _conversationRepository.IsParticipantAsync(roomId, userId))
        {
            await Clients.Caller.SendAsync("Error", new { message = "Not a participant of this conversation" });
            return;
        }

        if (!ConferenceRooms.TryGetValue(roomId, out var roomState))
        {
            // No active conference in this room, return empty list
            await Clients.Caller.SendAsync("RoomParticipants", new
            {
                roomId,
                participants = new List<UserDto>()
            });
            return;
        }

        var participants = roomState.Participants.Values.ToList();
        await Clients.Caller.SendAsync("RoomParticipants", new
        {
            roomId,
            participants
        });

        _logger.LogInformation("User {UserId} requested participants for room {RoomId}, returned {Count} participants", 
            userId, roomId, participants.Count);
    }

    /// <summary>
    /// Send offer to all participants in a room
    /// </summary>
    public async Task SendRoomOffer(string roomId, string sdp)
    {
        var fromUserId = GetUserId();
        if (string.IsNullOrEmpty(fromUserId)) return;

        if (!ConferenceRooms.TryGetValue(roomId, out var roomState))
        {
            return;
        }

        if (!await _conversationRepository.IsParticipantAsync(roomId, fromUserId))
        {
            await Clients.Caller.SendAsync("Error", new { message = "Not a participant of this conversation" });
            return;
        }

        // Send offer to all other participants (to all their devices)
        foreach (var participantId in roomState.Participants.Keys.Where(p => p != fromUserId))
        {
            foreach (var connectionId in GetAllConnectionIds(participantId))
            {
                await Clients.Client(connectionId).SendAsync("ReceiveOffer", new SignalingOffer(
                    fromUserId,
                    participantId,
                    roomId,
                    sdp
                ));
            }
        }
    }

    /// <summary>
    /// Send offer to 1 participant in a room
    /// </summary>
    public async Task SendOffer(string toUserId, string sdp, string roomId)
    {
        var fromUserId = GetUserId();
        if (string.IsNullOrEmpty(fromUserId)) return;

        if (!ConferenceRooms.TryGetValue(roomId, out var roomState))
        {
            return;
        }

        if (!await _conversationRepository.IsParticipantAsync(roomId, fromUserId))
        {
            await Clients.Caller.SendAsync("Error", new { message = "Not a participant of this conversation" });
            return;
        }

        // Send offer to the specific participant (to all their devices)
        foreach (var participantId in roomState.Participants.Keys.Where(p => p != fromUserId && p == toUserId))
        {
            foreach (var connectionId in GetAllConnectionIds(participantId))
            {
                await Clients.Client(connectionId).SendAsync("ReceiveOffer", new SignalingOffer(
                    fromUserId,
                    participantId,
                    roomId,
                    sdp
                ));
            }
        }
    }

    /// <summary>
    /// Send ICE candidate to all participants in a room
    /// </summary>
    public async Task SendRoomIceCandidate(string roomId, string candidate, string? sdpMid, int? sdpMLineIndex)
    {
        var fromUserId = GetUserId();
        if (string.IsNullOrEmpty(fromUserId)) return;

        if (!ConferenceRooms.TryGetValue(roomId, out var roomState))
        {
            return;
        }

        if (!await _conversationRepository.IsParticipantAsync(roomId, fromUserId))
        {
            await Clients.Caller.SendAsync("Error", new { message = "Not a participant of this conversation" });
            return;
        }

        // Send to all other participants (to all their devices)
        foreach (var participantId in roomState.Participants.Keys.Where(p => p != fromUserId))
        {
            foreach (var connectionId in GetAllConnectionIds(participantId))
            {
                await Clients.Client(connectionId).SendAsync("ReceiveIceCandidate", new SignalingIceCandidate(
                    fromUserId,
                    participantId,
                    roomId,
                    candidate,
                    sdpMid,
                    sdpMLineIndex
                ));
            }
        }
    }

    /// <summary>
    /// Send ICE candidate to a specific user
    /// </summary>
    public async Task SendIceCandidate(string toUserId, string candidate, string? sdpMid, int? sdpMLineIndex, string? roomId)
    {
        var fromUserId = GetUserId();
        if (string.IsNullOrEmpty(fromUserId)) return;

        // Send to all devices of the target user
        foreach (var connectionId in GetAllConnectionIds(toUserId))
        {
            await Clients.Client(connectionId).SendAsync("ReceiveIceCandidate", new SignalingIceCandidate(
                fromUserId,
                toUserId,
                roomId,
                candidate,
                sdpMid,
                sdpMLineIndex
            ));
        }

        _logger.LogDebug("ICE candidate sent from {FromUserId} to {ToUserId}", fromUserId, toUserId);
    }

    /// <summary>
    /// Send WebRTC answer
    /// </summary>
    public async Task SendAnswer(string toUserId, string sdp, string? roomId)
    {
        var fromUserId = GetUserId();
        if (string.IsNullOrEmpty(fromUserId)) return;

        // Send to all devices of the target user
        foreach (var connectionId in GetAllConnectionIds(toUserId))
        {
            await Clients.Client(connectionId).SendAsync("ReceiveAnswer", new SignalingAnswer(
                fromUserId,
                toUserId,
                roomId,
                sdp
            ));
        }

        _logger.LogDebug("Answer sent from {FromUserId} to {ToUserId}", fromUserId, toUserId);
    }

    #endregion

    #region Helper Methods

    private string? GetUserId()
    {
        return Context.User?.FindFirst("userId")?.Value;
    }

    /// <summary>
    /// Check if a user has any device connected
    /// </summary>
    private bool IsUserConnected(string userId)
    {
        return ConnectedUsers.TryGetValue(userId, out var devices) && !devices.IsEmpty;
    }

    /// <summary>
    /// Get the first connection ID for a user (for backward compatibility)
    /// </summary>
    private string? GetFirstConnectionId(string userId)
    {
        if (ConnectedUsers.TryGetValue(userId, out var devices))
        {
            return devices.Values.FirstOrDefault()?.ConnectionId;
        }
        return null;
    }

    /// <summary>
    /// Get all connection IDs for a user
    /// </summary>
    private IEnumerable<string> GetAllConnectionIds(string userId)
    {
        if (ConnectedUsers.TryGetValue(userId, out var devices))
        {
            return devices.Values.Select(d => d.ConnectionId);
        }
        return Enumerable.Empty<string>();
    }

    private async Task LeaveAllCalls(string userId)
    {
        // Find and end all active calls for this user
        var userCalls = ActiveCalls.Values
            .Where(c => c.CallerId == userId || c.Participants.Contains(userId))
            .ToList();

        foreach (var call in userCalls)
        {
            if (ActiveCalls.TryRemove(call.CallId, out _))
            {
                var otherUserIds = call.Participants.Where(i => i != userId);
                foreach (var otherUserId in otherUserIds)
                {
                    // Send to all devices of the other user
                    foreach (var connectionId in GetAllConnectionIds(otherUserId))
                    {
                        await Clients.Client(connectionId).SendAsync("CallEnded", new CallEnded(
                            call.CallId,
                            userId,
                            "disconnected"
                        ));
                    }
                }
            }
        }

        // Leave all conference rooms
        var userRooms = ConferenceRooms.Values
            .Where(r => r.Participants.ContainsKey(userId))
            .Select(r => r.RoomId)
            .ToList();

        foreach (var roomId in userRooms)
        {
            await LeaveRoomInternal(userId, roomId, "disconnected");
        }
    }

    private async Task LeaveRoomInternal(string userId, string roomId, string reason)
    {
        if (!ConferenceRooms.TryGetValue(roomId, out var roomState))
        {
            return;
        }

        if (!roomState.Participants.TryRemove(userId, out var userDto))
        {
            return;
        }

        await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"room_{roomId}");

        // Notify other participants
        await Clients.Group($"room_{roomId}").SendAsync("ParticipantLeft", new RoomParticipantUpdate(
            roomId,
            userDto,
            "left"
        ));
        await Clients.Group($"conversation_{roomId}").SendAsync("ParticipantLeft", new RoomParticipantUpdate(
            roomId,
            userDto,
            "left"
        ));

        // If room is empty, remove it
        if (roomState.Participants.IsEmpty)
        {
            ConferenceRooms.TryRemove(roomId, out _);
            _logger.LogInformation("Room {RoomId} removed (empty)", roomId);
        }

        _logger.LogInformation("User {UserId} left room {RoomId}: {Reason}", userId, roomId, reason);
    }

    #endregion
}

#region Internal Classes

internal class CallInfo
{
    public string CallId { get; set; } = string.Empty;
    public string CallerId { get; set; } = string.Empty;
    public ConcurrentBag<string> Participants { get; set; } = new ConcurrentBag<string>();
    public ConcurrentBag<string> PendingParticipants { get; set; } = new ConcurrentBag<string>();
    public string CallType { get; set; } = string.Empty;
    public DateTime StartedAt { get; set; }
    public bool IsAccepted { get; set; }
}

internal class RoomState
{
    public string RoomId { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string CreatedBy { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
    public ConcurrentDictionary<string, UserDto> Participants { get; } = new();
}

internal class DeviceInfo
{
    public string ConnectionId { get; }
    public string DeviceId { get; }
    public DateTime ConnectedAt { get; }

    public DeviceInfo(string connectionId, string deviceId, DateTime connectedAt)
    {
        ConnectionId = connectionId;
        DeviceId = deviceId;
        ConnectedAt = connectedAt;
    }
}

#endregion
