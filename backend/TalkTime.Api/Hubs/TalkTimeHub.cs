using System.Collections.Concurrent;
using System.Security.Cryptography;
using Microsoft.AspNetCore.SignalR;
using TalkTime.Core.DTOs;
using TalkTime.Core.Entities;
using TalkTime.Core.Enums;
using TalkTime.Core.Interfaces;

namespace TalkTime.Api.Hubs;

/// <summary>
/// SignalR Hub for real-time messaging and WebRTC signaling.
/// Connections are tracked by deviceId so both authenticated users and guests
/// can participate. UserId is kept on each connection for internal features
/// (conversations, messages, online status).
/// </summary>
public class TalkTimeHub : Hub
{
    private readonly IUserRepository _userRepository;
    private readonly IConversationRepository _conversationRepository;
    private readonly IMessageRepository _messageRepository;
    private readonly INotificationsService _notificationsService;
    private readonly ILogger<TalkTimeHub> _logger;

    // Primary tracking: deviceId -> ConnectionInfo
    private static readonly ConcurrentDictionary<string, ConnectionInfo> ConnectedDevices = new();

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
        var deviceId = GetDeviceId();
        var guestName = Context.GetHttpContext()?.Request.Query["guestName"].FirstOrDefault();
        var isGuest = string.IsNullOrEmpty(userId);

        if (isGuest && string.IsNullOrEmpty(guestName))
        {
            _logger.LogWarning("Rejecting connection: no auth and no guestName");
            Context.Abort();
            return;
        }

        string displayName;
        if (isGuest)
        {
            displayName = guestName!;
        }
        else
        {
            var user = await _userRepository.GetByIdAsync(userId!);
            displayName = user?.Username ?? "Unknown";
        }

        var connectionInfo = new ConnectionInfo(
            Context.ConnectionId, deviceId, userId, displayName, DateTime.UtcNow, isGuest);
        ConnectedDevices[deviceId] = connectionInfo;

        if (!isGuest)
        {
            // Notify other devices of the same user
            var otherDevices = ConnectedDevices.Values
                .Where(c => c.UserId == userId && c.ConnectionId != Context.ConnectionId)
                .ToList();

            if (otherDevices.Any())
            {
                var deviceConnectedEvent = new DeviceConnectedEvent(
                    userId!,
                    deviceId,
                    otherDevices.Count + 1
                );

                foreach (var otherDevice in otherDevices)
                {
                    await Clients.Client(otherDevice.ConnectionId)
                        .SendAsync("DeviceConnected", deviceConnectedEvent);
                }

                await Clients.Caller.SendAsync("OtherDevicesAvailable", new
                {
                    otherDeviceCount = otherDevices.Count,
                    totalDevices = otherDevices.Count + 1,
                    otherDeviceIds = otherDevices.Select(d => d.DeviceId).ToList()
                });

                _logger.LogInformation(
                    "User {UserId} connected new device {DeviceId}. Total devices: {TotalDevices}.",
                    userId, deviceId, otherDevices.Count + 1);
            }
            else
            {
                _logger.LogInformation(
                    "User {UserId} connected device {DeviceId}. This is the only device.",
                    userId, deviceId);
            }

            await _userRepository.SetOnlineStatusAsync(userId!, true);

            var conversations = await _conversationRepository.GetUserConversationsAsync(userId!);
            foreach (var conversation in conversations)
            {
                await Groups.AddToGroupAsync(Context.ConnectionId, $"conversation_{conversation.Id}");
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

            var pendingMessages = await _messageRepository.GetPendingMessagesForUserAsync(userId!);
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
                await _messageRepository.MarkAsDeliveredAsync(message.Id, userId!);
            }
        }

        _logger.LogInformation(
            "{Kind} connected: deviceId={DeviceId}, connectionId={ConnectionId}, displayName={DisplayName}",
            isGuest ? "Guest" : "User", deviceId, Context.ConnectionId, displayName);

        await base.OnConnectedAsync();
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        var connInfo = GetCurrentConnectionInfo();
        if (connInfo != null)
        {
            ConnectedDevices.TryRemove(connInfo.DeviceId, out _);

            if (!connInfo.IsGuest && connInfo.UserId != null)
            {
                var hasOtherDevices = ConnectedDevices.Values.Any(c => c.UserId == connInfo.UserId);

                if (!hasOtherDevices)
                {
                    await _userRepository.SetOnlineStatusAsync(connInfo.UserId, false);
                    await Clients.Others.SendAsync("UserOffline", new { userId = connInfo.UserId, lastSeenAt = DateTime.UtcNow.ToString("o") });
                }
                else
                {
                    var otherDevices = ConnectedDevices.Values
                        .Where(c => c.UserId == connInfo.UserId)
                        .ToList();
                    var deviceDisconnectedEvent = new
                    {
                        UserId = connInfo.UserId,
                        DeviceId = connInfo.DeviceId,
                        TotalDevices = otherDevices.Count
                    };
                    foreach (var otherDevice in otherDevices)
                    {
                        await Clients.Client(otherDevice.ConnectionId)
                            .SendAsync("DeviceDisconnected", deviceDisconnectedEvent);
                    }
                }
            }

            await LeaveAllCalls(connInfo.DeviceId);

            _logger.LogInformation(
                "{Kind} disconnected: deviceId={DeviceId}, connectionId={ConnectionId}",
                connInfo.IsGuest ? "Guest" : "User", connInfo.DeviceId, Context.ConnectionId);
        }

        await base.OnDisconnectedAsync(exception);
    }

    #region Messaging (authenticated only)

    public async Task JoinConversation(string conversationId)
    {
        var connInfo = GetCurrentConnectionInfo();
        if (connInfo == null || connInfo.IsGuest || connInfo.UserId == null) return;
        var userId = connInfo.UserId;

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

    public async Task LeaveConversation(string conversationId)
    {
        await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"conversation_{conversationId}");
        _logger.LogInformation("Connection {ConnectionId} left conversation {ConversationId}", Context.ConnectionId, conversationId);
    }

    public async Task SendTypingIndicator(string conversationId, bool isTyping)
    {
        var connInfo = GetCurrentConnectionInfo();
        if (connInfo == null || connInfo.IsGuest || connInfo.UserId == null) return;

        try
        {
            await Clients.OthersInGroup($"conversation_{conversationId}")
                .SendAsync("TypingIndicator", new { conversationId, userId = connInfo.UserId, isTyping });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send typing indicator to conversation {ConversationId}", conversationId);
        }
    }

    public async Task AcknowledgeMessage(string messageId)
    {
        var connInfo = GetCurrentConnectionInfo();
        if (connInfo == null || connInfo.IsGuest || connInfo.UserId == null) return;

        await _messageRepository.MarkAsDeliveredAsync(messageId, connInfo.UserId);
        _logger.LogInformation("User {UserId} acknowledged message {MessageId}", connInfo.UserId, messageId);
    }

    #endregion

    #region Device Sync (authenticated only)

    public async Task RequestDeviceSync(string conversationId, long sinceTimestamp, int chunkSize = 100)
    {
        var connInfo = GetCurrentConnectionInfo();
        if (connInfo == null || connInfo.IsGuest || connInfo.UserId == null) return;

        var actualConversationId = string.IsNullOrEmpty(conversationId) ? null : conversationId;
        var actualSinceTimestamp = sinceTimestamp == 0 ? (long?)null : sinceTimestamp;

        var syncRequest = new DeviceSyncRequest(
            connInfo.DeviceId,
            actualConversationId,
            actualSinceTimestamp,
            chunkSize
        );

        var otherDevices = ConnectedDevices.Values
            .Where(c => c.UserId == connInfo.UserId && c.ConnectionId != Context.ConnectionId)
            .ToList();

        foreach (var device in otherDevices)
        {
            await Clients.Client(device.ConnectionId).SendAsync("DeviceSyncRequest", syncRequest);
        }

        _logger.LogInformation(
            "User {UserId} device {DeviceId} requested sync from {OtherDeviceCount} other devices",
            connInfo.UserId, connInfo.DeviceId, otherDevices.Count);
    }

    public async Task SendDeviceSyncData(string toDeviceId, string conversationId, List<SyncMessageDto> messages, int chunkIndex, int totalChunks, bool isLastChunk)
    {
        var connInfo = GetCurrentConnectionInfo();
        if (connInfo == null || connInfo.IsGuest || connInfo.UserId == null) return;

        var actualConversationId = string.IsNullOrEmpty(conversationId) ? null : conversationId;

        var targetDevice = ConnectedDevices.Values
            .FirstOrDefault(d => d.DeviceId == toDeviceId && d.UserId == connInfo.UserId);

        if (targetDevice == null)
        {
            _logger.LogWarning(
                "User {UserId} device {DeviceId} tried to send sync data to unknown device {ToDeviceId}",
                connInfo.UserId, connInfo.DeviceId, toDeviceId);
            return;
        }

        var syncChunk = new DeviceSyncChunk(
            connInfo.DeviceId,
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
            connInfo.UserId, connInfo.DeviceId, chunkIndex, totalChunks, messages.Count, toDeviceId);
    }

    public async Task GetConnectedDevices()
    {
        var connInfo = GetCurrentConnectionInfo();
        if (connInfo == null || connInfo.IsGuest || connInfo.UserId == null) return;

        var userDevices = ConnectedDevices.Values
            .Where(c => c.UserId == connInfo.UserId)
            .Select(d => new
            {
                deviceId = d.DeviceId,
                connectedAt = d.ConnectedAt.ToString("o"),
                isCurrentDevice = d.ConnectionId == Context.ConnectionId
            }).ToList();

        await Clients.Caller.SendAsync("ConnectedDevices", new { devices = userDevices });
    }

    #endregion

    #region WebRTC Signaling - Conference Rooms

    /// <summary>
    /// Create a new conference room (authenticated users only).
    /// </summary>
    /// <param name="roomName">ConversationId</param>
    public async Task CreateRoom(string roomName)
    {
        var connInfo = GetCurrentConnectionInfo();
        if (connInfo == null || connInfo.IsGuest || connInfo.UserId == null) return;
        var userId = connInfo.UserId;
        var deviceId = connInfo.DeviceId;

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

        var inviteKey = RoomState.GenerateInviteKey();
        var roomState = new RoomState
        {
            RoomId = roomName,
            Name = roomName,
            CreatedBy = userId,
            CreatedAt = DateTime.UtcNow,
            InviteKey = inviteKey
        };

        ConferenceRooms[roomName] = roomState;

        await JoinRoom(roomName);

        var participantDto = new UserDto(deviceId, user.Username, user.AvatarUrl, user.Description, user.IsOnline, user.LastSeenAt);
        await Clients.Caller.SendAsync("RoomCreated", new RoomInfo(
            roomName,
            roomName,
            new List<UserDto> { participantDto },
            userId,
            roomState.CreatedAt,
            inviteKey
        ));

        _logger.LogInformation("Room {RoomId} created by user {UserId} (device {DeviceId}), inviteKey generated", roomName, userId, deviceId);
    }

    /// <summary>
    /// Join an existing conference room (authenticated users).
    /// Participants are tracked by deviceId for signaling compatibility with guests.
    /// </summary>
    public async Task JoinRoom(string roomId)
    {
        var connInfo = GetCurrentConnectionInfo();
        if (connInfo == null || connInfo.IsGuest || connInfo.UserId == null) return;
        var userId = connInfo.UserId;
        var deviceId = connInfo.DeviceId;

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

        if (roomState.Participants.ContainsKey(deviceId))
        {
            return;
        }

        var user = await _userRepository.GetByIdAsync(userId);
        if (user == null) return;

        // UserDto.Id = deviceId so signaling targets the right device
        var userDto = new UserDto(deviceId, user.Username, user.AvatarUrl, user.Description, user.IsOnline, user.LastSeenAt);

        roomState.Participants[deviceId] = userDto;

        await Groups.AddToGroupAsync(Context.ConnectionId, $"room_{roomId}");

        await Clients.OthersInGroup($"room_{roomId}").SendAsync("ParticipantJoined", new RoomParticipantUpdate(
            roomId, userDto, "joined"
        ));

        await Clients.Group($"conversation_{roomId}").SendAsync("ParticipantJoined", new RoomParticipantUpdate(
            roomId, userDto, "joined"
        ));

        var participants = roomState.Participants.Values.ToList();
        await Clients.Caller.SendAsync("RoomJoined", new RoomInfo(
            roomId,
            roomState.Name,
            participants,
            roomState.CreatedBy,
            roomState.CreatedAt,
            roomState.InviteKey
        ));

        foreach (var c in roomState.Participants.ToArray())
        {
            if (c.Key == deviceId) continue;
            await Clients.Caller.SendAsync("ParticipantJoined", new RoomParticipantUpdate(
                roomId, c.Value, "joined"
            ));
        }

        _logger.LogInformation("User {UserId} (device {DeviceId}) joined room {RoomId}", userId, deviceId, roomId);

        if (roomState.Participants.Count == 1)
        {
            var conversations = await _conversationRepository.GetByIdWithParticipantsAsync(roomId);
            foreach (var participant in conversations?.Participants ?? Array.Empty<ConversationParticipant>())
            {
                if (participant.UserId != userId)
                {
                    var targetConns = ConnectedDevices.Values
                        .Where(c => c.UserId == participant.UserId)
                        .ToList();

                    if (targetConns.Any())
                    {
                        foreach (var conn in targetConns)
                        {
                            await Clients.Client(conn.ConnectionId).SendAsync("CallInitiated", new RoomParticipantUpdate(
                                roomId, userDto, "joined"
                            ));
                        }
                    }

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
                            conversations!.Type == ConversationType.Direct ? "Calling you" : "Calling in group",
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

    /// <summary>
    /// Join an existing conference room as a guest using the invite key.
    /// The room must already exist (created by an authenticated user).
    /// </summary>
    public async Task JoinRoomAsGuest(string inviteKey, string displayName)
    {
        var connInfo = GetCurrentConnectionInfo();
        if (connInfo == null) return;
        var deviceId = connInfo.DeviceId;

        // Look up room by invite key
        var roomEntry = ConferenceRooms.FirstOrDefault(r =>
            string.Equals(r.Value.InviteKey, inviteKey, StringComparison.Ordinal));

        if (roomEntry.Value == null)
        {
            await Clients.Caller.SendAsync("Error", new { message = "Invalid or expired invite link" });
            return;
        }

        var roomState = roomEntry.Value;
        var roomId = roomState.RoomId;

        if (roomState.Participants.ContainsKey(deviceId))
        {
            return;
        }

        var userDto = new UserDto(deviceId, displayName, null, null, true, null);
        roomState.Participants[deviceId] = userDto;

        await Groups.AddToGroupAsync(Context.ConnectionId, $"room_{roomId}");

        await Clients.OthersInGroup($"room_{roomId}").SendAsync("ParticipantJoined", new RoomParticipantUpdate(
            roomId, userDto, "joined"
        ));

        var participants = roomState.Participants.Values.ToList();
        await Clients.Caller.SendAsync("RoomJoined", new RoomInfo(
            roomId,
            roomState.Name,
            participants,
            roomState.CreatedBy,
            roomState.CreatedAt
        ));

        foreach (var c in roomState.Participants.ToArray())
        {
            if (c.Key == deviceId) continue;
            await Clients.Caller.SendAsync("ParticipantJoined", new RoomParticipantUpdate(
                roomId, c.Value, "joined"
            ));
        }

        _logger.LogInformation("Guest {DisplayName} (device {DeviceId}) joined room {RoomId} via invite key", displayName, deviceId, roomId);
    }

    /// <summary>
    /// Leave a conference room
    /// </summary>
    public async Task LeaveRoom(string roomId, string reason)
    {
        var connInfo = GetCurrentConnectionInfo();
        if (connInfo == null) return;

        await LeaveRoomInternal(connInfo.DeviceId, roomId, reason);
    }

    /// <summary>
    /// Get current participants in a conference room
    /// </summary>
    public async Task GetRoomParticipants(string roomId)
    {
        var connInfo = GetCurrentConnectionInfo();
        if (connInfo == null) return;

        // For authenticated users, verify conversation participation
        if (!connInfo.IsGuest && connInfo.UserId != null)
        {
            if (!await _conversationRepository.IsParticipantAsync(roomId, connInfo.UserId))
            {
                await Clients.Caller.SendAsync("Error", new { message = "Not a participant of this conversation" });
                return;
            }
        }

        if (!ConferenceRooms.TryGetValue(roomId, out var roomState))
        {
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

        _logger.LogInformation("Device {DeviceId} requested participants for room {RoomId}, returned {Count} participants",
            connInfo.DeviceId, roomId, participants.Count);
    }

    /// <summary>
    /// Send offer to all participants in a room
    /// </summary>
    public async Task SendRoomOffer(string roomId, string sdp)
    {
        var connInfo = GetCurrentConnectionInfo();
        if (connInfo == null) return;
        var fromDeviceId = connInfo.DeviceId;

        if (!ConferenceRooms.TryGetValue(roomId, out var roomState)) return;
        if (!roomState.Participants.ContainsKey(fromDeviceId)) return;

        foreach (var targetDeviceId in roomState.Participants.Keys.Where(p => p != fromDeviceId))
        {
            if (ConnectedDevices.TryGetValue(targetDeviceId, out var targetConn))
            {
                await Clients.Client(targetConn.ConnectionId).SendAsync("ReceiveOffer", new SignalingOffer(
                    fromDeviceId, targetDeviceId, roomId, sdp
                ));
            }
        }
    }

    /// <summary>
    /// Send offer to 1 participant in a room (by deviceId)
    /// </summary>
    public async Task SendOffer(string toDeviceId, string sdp, string roomId)
    {
        var connInfo = GetCurrentConnectionInfo();
        if (connInfo == null) return;
        var fromDeviceId = connInfo.DeviceId;

        if (!ConferenceRooms.TryGetValue(roomId, out var roomState)) return;
        if (!roomState.Participants.ContainsKey(fromDeviceId)) return;

        if (roomState.Participants.ContainsKey(toDeviceId) && ConnectedDevices.TryGetValue(toDeviceId, out var targetConn))
        {
            await Clients.Client(targetConn.ConnectionId).SendAsync("ReceiveOffer", new SignalingOffer(
                fromDeviceId, toDeviceId, roomId, sdp
            ));
        }
    }

    /// <summary>
    /// Send ICE candidate to all participants in a room
    /// </summary>
    public async Task SendRoomIceCandidate(string roomId, string candidate, string? sdpMid, int? sdpMLineIndex)
    {
        var connInfo = GetCurrentConnectionInfo();
        if (connInfo == null) return;
        var fromDeviceId = connInfo.DeviceId;

        if (!ConferenceRooms.TryGetValue(roomId, out var roomState)) return;
        if (!roomState.Participants.ContainsKey(fromDeviceId)) return;

        foreach (var targetDeviceId in roomState.Participants.Keys.Where(p => p != fromDeviceId))
        {
            if (ConnectedDevices.TryGetValue(targetDeviceId, out var targetConn))
            {
                await Clients.Client(targetConn.ConnectionId).SendAsync("ReceiveIceCandidate", new SignalingIceCandidate(
                    fromDeviceId, targetDeviceId, roomId, candidate, sdpMid, sdpMLineIndex
                ));
            }
        }
    }

    /// <summary>
    /// Send ICE candidate to a specific device
    /// </summary>
    public async Task SendIceCandidate(string toDeviceId, string candidate, string? sdpMid, int? sdpMLineIndex, string? roomId)
    {
        var connInfo = GetCurrentConnectionInfo();
        if (connInfo == null) return;
        var fromDeviceId = connInfo.DeviceId;

        if (ConnectedDevices.TryGetValue(toDeviceId, out var targetConn))
        {
            await Clients.Client(targetConn.ConnectionId).SendAsync("ReceiveIceCandidate", new SignalingIceCandidate(
                fromDeviceId, toDeviceId, roomId, candidate, sdpMid, sdpMLineIndex
            ));
        }

        _logger.LogDebug("ICE candidate sent from {FromDeviceId} to {ToDeviceId}", fromDeviceId, toDeviceId);
    }

    /// <summary>
    /// Send WebRTC answer
    /// </summary>
    public async Task SendAnswer(string toDeviceId, string sdp, string? roomId)
    {
        var connInfo = GetCurrentConnectionInfo();
        if (connInfo == null) return;
        var fromDeviceId = connInfo.DeviceId;

        if (ConnectedDevices.TryGetValue(toDeviceId, out var targetConn))
        {
            await Clients.Client(targetConn.ConnectionId).SendAsync("ReceiveAnswer", new SignalingAnswer(
                fromDeviceId, toDeviceId, roomId, sdp
            ));
        }

        _logger.LogDebug("Answer sent from {FromDeviceId} to {ToDeviceId}", fromDeviceId, toDeviceId);
    }

    #endregion

    #region Helper Methods

    private string? GetUserId()
    {
        return Context.User?.FindFirst("userId")?.Value;
    }

    private string GetDeviceId()
    {
        return Context.GetHttpContext()?.Request.Query["deviceId"].FirstOrDefault()
            ?? Context.ConnectionId;
    }

    private ConnectionInfo? GetCurrentConnectionInfo()
    {
        return ConnectedDevices.Values.FirstOrDefault(c => c.ConnectionId == Context.ConnectionId);
    }

    private bool IsUserConnected(string userId)
    {
        return ConnectedDevices.Values.Any(c => c.UserId == userId);
    }

    private async Task LeaveAllCalls(string deviceId)
    {
        // Find and end all active calls involving this device
        var deviceCalls = ActiveCalls.Values
            .Where(c => c.CallerId == deviceId || c.Participants.Contains(deviceId))
            .ToList();

        foreach (var call in deviceCalls)
        {
            if (ActiveCalls.TryRemove(call.CallId, out _))
            {
                var otherDeviceIds = call.Participants.Where(i => i != deviceId);
                foreach (var otherDeviceId in otherDeviceIds)
                {
                    if (ConnectedDevices.TryGetValue(otherDeviceId, out var otherConn))
                    {
                        await Clients.Client(otherConn.ConnectionId).SendAsync("CallEnded", new CallEnded(
                            call.CallId, deviceId, "disconnected"
                        ));
                    }
                }
            }
        }

        // Leave all conference rooms
        var deviceRooms = ConferenceRooms.Values
            .Where(r => r.Participants.ContainsKey(deviceId))
            .Select(r => r.RoomId)
            .ToList();

        foreach (var roomId in deviceRooms)
        {
            await LeaveRoomInternal(deviceId, roomId, "disconnected");
        }
    }

    private async Task LeaveRoomInternal(string deviceId, string roomId, string reason)
    {
        if (!ConferenceRooms.TryGetValue(roomId, out var roomState))
        {
            return;
        }

        if (!roomState.Participants.TryRemove(deviceId, out var userDto))
        {
            return;
        }

        await Groups.RemoveFromGroupAsync(Context.ConnectionId, $"room_{roomId}");

        await Clients.Group($"room_{roomId}").SendAsync("ParticipantLeft", new RoomParticipantUpdate(
            roomId, userDto, "left"
        ));
        await Clients.Group($"conversation_{roomId}").SendAsync("ParticipantLeft", new RoomParticipantUpdate(
            roomId, userDto, "left"
        ));

        if (roomState.Participants.IsEmpty)
        {
            ConferenceRooms.TryRemove(roomId, out _);
            _logger.LogInformation("Room {RoomId} removed (empty)", roomId);
        }

        _logger.LogInformation("Device {DeviceId} left room {RoomId}: {Reason}", deviceId, roomId, reason);
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
    /// <summary>64-char hex token guests must present to join this room.</summary>
    public string InviteKey { get; set; } = string.Empty;
    /// <summary>deviceId -> UserDto (UserDto.Id = deviceId for signaling)</summary>
    public ConcurrentDictionary<string, UserDto> Participants { get; } = new();

    public static string GenerateInviteKey()
    {
        var bytes = new byte[32]; // 32 bytes = 64 hex chars
        RandomNumberGenerator.Fill(bytes);
        return Convert.ToHexString(bytes).ToLowerInvariant();
    }
}

internal class ConnectionInfo
{
    public string ConnectionId { get; }
    public string DeviceId { get; }
    public string? UserId { get; }
    public string DisplayName { get; }
    public DateTime ConnectedAt { get; }
    public bool IsGuest { get; }

    public ConnectionInfo(string connectionId, string deviceId, string? userId, string displayName, DateTime connectedAt, bool isGuest)
    {
        ConnectionId = connectionId;
        DeviceId = deviceId;
        UserId = userId;
        DisplayName = displayName;
        ConnectedAt = connectedAt;
        IsGuest = isGuest;
    }
}

#endregion
