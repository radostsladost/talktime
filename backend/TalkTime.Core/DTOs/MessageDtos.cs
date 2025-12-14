using TalkTime.Core.Enums;

namespace TalkTime.Core.DTOs;

// Response DTOs
public record MessageDto(
    string Id,
    string ConversationId,
    UserDto Sender,
    string Content, // Encrypted content from frontend
    string Type,
    string SentAt
);

public record MessagesResponseDto(
    List<MessageDto> Data
);

// Request DTOs
public record SendMessageRequest(
    string ConversationId,
    string Content // Encrypted by frontend
);

public record SendMessageResponseDto(
    MessageDto Data
);
