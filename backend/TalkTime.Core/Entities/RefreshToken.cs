namespace TalkTime.Core.Entities;

public class RefreshToken
{
    public string Id { get; set; } = Guid.NewGuid().ToString();

    /// <summary>
    /// The hashed refresh token value
    /// </summary>
    public string TokenHash { get; set; } = string.Empty;

    /// <summary>
    /// The user this refresh token belongs to
    /// </summary>
    public string UserId { get; set; } = string.Empty;

    /// <summary>
    /// When this refresh token expires
    /// </summary>
    public DateTime ExpiresAt { get; set; }

    /// <summary>
    /// When this refresh token was created
    /// </summary>
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// When this refresh token was revoked (null if still valid)
    /// </summary>
    public DateTime? RevokedAt { get; set; }

    /// <summary>
    /// The token that replaced this one (for token rotation)
    /// </summary>
    public string? ReplacedByTokenId { get; set; }

    /// <summary>
    /// Optional device/client information for the token
    /// </summary>
    public string? DeviceInfo { get; set; }

    /// <summary>
    /// IP address from which the token was created
    /// </summary>
    public string? IpAddress { get; set; }

    // Navigation property
    public User User { get; set; } = null!;

    /// <summary>
    /// Check if the token is expired
    /// </summary>
    public bool IsExpired => DateTime.UtcNow >= ExpiresAt;

    /// <summary>
    /// Check if the token has been revoked
    /// </summary>
    public bool IsRevoked => RevokedAt != null;

    /// <summary>
    /// Check if the token is still active (not expired and not revoked)
    /// </summary>
    public bool IsActive => !IsRevoked && !IsExpired;
}
