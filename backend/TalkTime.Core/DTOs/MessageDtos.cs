using TalkTime.Core.Enums;

namespace TalkTime.Core.DTOs;

// Response DTOs
public record MessageDto(
    string Id,
    string ConversationId,
    UserDto Sender,
    string Content, // Encrypted content from frontend
    string Type,
    string SentAt,
    string? MediaUrl = null,
    string? ThumbnailUrl = null,
    List<ReactionDto>? Reactions = null
);

public record ReactionDto(
    string Id,
    string Emoji,
    string UserId,
    string Username
);

public record ReactionSummaryDto(
    string Emoji,
    int Count,
    List<string> UserIds
);

public record MessagesResponseDto(
    List<MessageDto> Data
);

// Request DTOs
public record SendMessageRequest(
    string ConversationId,
    string Content, // Encrypted by frontend
    string Type = "text",
    string? MediaUrl = null
);

public record AddReactionRequest(
    string ConversationId,
    string MessageId,
    string Emoji
);

public record RemoveReactionRequest(
    string ConversationId,
    string MessageId,
    string Emoji
);

public record SendMessageResponseDto(
    MessageDto Data
);

// ==================== Device Sync DTOs ====================

/// <summary>
/// Represents a device connection info for multi-device sync
/// </summary>
public record DeviceInfo(
    string ConnectionId,
    string DeviceId,
    DateTime ConnectedAt
);

/// <summary>
/// Event sent when a new device connects for the same user
/// </summary>
public record DeviceConnectedEvent(
    string UserId,
    string DeviceId,
    int TotalDevices
);

/// <summary>
/// Request to sync messages from other devices
/// </summary>
public record DeviceSyncRequest(
    string RequestingDeviceId,
    string? ConversationId,       // null = all conversations
    long? SinceTimestamp,         // Unix timestamp in milliseconds
    int ChunkSize = 100
);

/// <summary>
/// A chunk of messages for device sync
/// </summary>
public record DeviceSyncChunk(
    string FromDeviceId,
    string ToDeviceId,
    string? ConversationId,
    List<SyncMessageDto> Messages,
    int ChunkIndex,
    int TotalChunks,
    bool IsLastChunk
);

/// <summary>
/// Simplified message DTO for sync (includes all data needed to reconstruct message locally)
/// </summary>
public record SyncMessageDto(
    string Id,
    string ConversationId,
    string SenderId,
    string SenderUsername,
    string? SenderAvatarUrl,
    string Content,
    string Type,
    long SentAtTimestamp,       // Unix timestamp in milliseconds
    string? MediaUrl,
    string? ThumbnailUrl,
    long? ReadAtTimestamp       // Unix timestamp in milliseconds, null if unread
);
