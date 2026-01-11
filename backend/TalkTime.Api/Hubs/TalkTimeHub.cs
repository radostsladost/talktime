using System.Collections.Concurrent;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using TalkTime.Core.DTOs;
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
    private readonly ILogger<TalkTimeHub> _logger;

    // Track connected users: userId -> connectionId
    private static readonly ConcurrentDictionary<string, string> ConnectedUsers = new();

    // Track active calls: callId -> CallInfo
    private static readonly ConcurrentDictionary<string, CallInfo> ActiveCalls = new();

    // Track conference rooms: roomId -> RoomState
    private static readonly ConcurrentDictionary<string, RoomState> ConferenceRooms = new();

    public TalkTimeHub(
        IUserRepository userRepository,
        IConversationRepository conversationRepository,
        IMessageRepository messageRepository,
        ILogger<TalkTimeHub> logger)
    {
        _userRepository = userRepository;
        _conversationRepository = conversationRepository;
        _messageRepository = messageRepository;
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

        ConnectedUsers[userId] = Context.ConnectionId;

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


        // Send pending messages to the user
        var pendingMessages = await _messageRepository.GetPendingMessagesForUserAsync(userId);
        foreach (var message in pendingMessages)
        {
            var messageDto = new MessageDto(
                message.Id,
                message.ConversationId,
                new UserDto(message.Sender.Id, message.Sender.Username, message.Sender.AvatarUrl),
                message.EncryptedContent,
                message.Type.ToString().ToLower(),
                message.SentAt.ToString("o")
            );
            await Clients.Caller.SendAsync("ReceiveMessage", messageDto);

            // Mark as delivered
            await _messageRepository.MarkAsDeliveredAsync(message.Id, userId);
        }

        _logger.LogInformation("User {UserId} connected with connection {ConnectionId}", userId, Context.ConnectionId);

        await base.OnConnectedAsync();
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        var userId = GetUserId();
        if (!string.IsNullOrEmpty(userId))
        {
            ConnectedUsers.TryRemove(userId, out _);

            // Update user online status
            await _userRepository.SetOnlineStatusAsync(userId, false);

            // Leave any active calls
            await LeaveAllCalls(userId);

            // Notify others that user is offline
            await Clients.Others.SendAsync("UserOffline", new { userId, lastSeenAt = DateTime.UtcNow.ToString("o") });

            _logger.LogInformation("User {UserId} disconnected", userId);
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
            new List<UserDto> { new(user.Id, user.Username, user.AvatarUrl) },
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

        var userDto = new UserDto(user.Id, user.Username, user.AvatarUrl);

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

        // Send current participants to the new user
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
            if (c.Value == userDto)
                continue;

            await Clients.Caller.SendAsync("ParticipantJoined", new RoomParticipantUpdate(
                roomId,
                c.Value,
                "joined"
            ));
        }

        _logger.LogInformation("User {UserId} joined room {RoomId}", userId, roomId);
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

        // Send offer to all other participants
        foreach (var participantId in roomState.Participants.Keys.Where(p => p != fromUserId))
        {
            if (ConnectedUsers.TryGetValue(participantId, out var connectionId))
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

        // Send to all other participants
        foreach (var participantId in roomState.Participants.Keys.Where(p => p != fromUserId))
        {
            if (ConnectedUsers.TryGetValue(participantId, out var connectionId))
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
    /// Send WebRTC answer
    /// </summary>
    public async Task SendAnswer(string toUserId, string sdp, string? roomId)
    {
        var fromUserId = GetUserId();
        if (string.IsNullOrEmpty(fromUserId)) return;

        if (ConnectedUsers.TryGetValue(toUserId, out var connectionId))
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
                    if (ConnectedUsers.TryGetValue(otherUserId, out var connectionId))
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

#endregion
