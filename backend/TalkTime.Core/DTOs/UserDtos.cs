namespace TalkTime.Core.DTOs;

// Response DTOs
public record UserDto(
    string Id,
    string Username,
    string? AvatarUrl,
    string? Description,
    bool IsOnline,
    DateTime? LastSeenAt
);

public record UserProfileDto(
    string Id,
    string Username,
    string? AvatarUrl,
    string? Email,
    string? Description
);

// Request DTOs
public record RegisterRequest(
    string Username,
    string Email,
    string Password,
    string? FirebaseToken = null,
    string? DeviceId = null,
    string? DeviceInfo = null
);

public record LoginRequest(
    string Email,
    string Password,
    string? FirebaseToken = null,
    string? DeviceId = null,
    string? DeviceInfo = null
);

public record LoginResponse(
    string AccessToken,
    string RefreshToken,
    DateTime AccessTokenExpires,
    DateTime RefreshTokenExpires,
    UserProfileDto User
);

public record UpdateProfileRequest(
    string? Username,
    string? Email,
    string? Description,
    string? Password,
    string? NewPassword
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

// Firebase Token DTOs
public record RegisterFirebaseTokenRequest(
    string Token,
    string? DeviceId,
    string? DeviceInfo,
    bool? MessagePreview = true
);

public record DeleteFirebaseTokenRequest(string Token);