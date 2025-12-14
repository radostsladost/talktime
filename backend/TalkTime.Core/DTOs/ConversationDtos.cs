using TalkTime.Core.Enums;

namespace TalkTime.Core.DTOs;

// Response DTOs
public record ConversationDto(
    string Id,
    string Type,
    string? Name,
    List<UserDto> Participants,
    string? LastMessage,
    string? LastMessageAt
);

public record ConversationDetailDto(
    string Id,
    string Type,
    string? Name,
    List<UserDto> Participants,
    DateTime CreatedAt
);

// Request DTOs
public record CreateConversationRequest(
    string Type,
    string? Name,
    List<string> ParticipantIds
);

public record CreateGroupRequest(
    string Name,
    List<string> ParticipantIds
);

public record AddParticipantRequest(
    string UserId
);

public record RemoveParticipantRequest(
    string UserId
);

public record UpdateConversationRequest(
    string? Name
);
