namespace TalkTime.Core.DTOs;

// Response DTOs
public record UserDto(
    string Id,
    string Username,
    string? AvatarUrl
);

public record UserDetailDto(
    string Id,
    string Username,
    string Email,
    string? AvatarUrl,
    bool IsOnline,
    DateTime? LastSeenAt
);

// Request DTOs
public record RegisterRequest(
    string Username,
    string Email,
    string Password
);

public record LoginRequest(
    string Email,
    string Password
);

public record LoginResponse(
    string Token,
    UserDto User
);

public record UpdateProfileRequest(
    string? Username,
    string? AvatarUrl
);
