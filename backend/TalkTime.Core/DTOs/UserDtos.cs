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
    string AccessToken,
    string RefreshToken,
    DateTime AccessTokenExpires,
    DateTime RefreshTokenExpires,
    UserDto User
);

public record UpdateProfileRequest(
    string? Username,
    string? AvatarUrl
);

// Refresh Token DTOs
public record RefreshTokenRequest(
    string RefreshToken
);

public record RefreshTokenResponse(
    string AccessToken,
    string RefreshToken,
    DateTime AccessTokenExpires,
    DateTime RefreshTokenExpires
);

public record RevokeTokenRequest(
    string RefreshToken
);
