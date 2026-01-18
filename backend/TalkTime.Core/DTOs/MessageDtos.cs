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
