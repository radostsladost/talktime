using TalkTime.Core.Entities;

namespace TalkTime.Core.Interfaces;

public interface IRefreshTokenRepository
{
    /// <summary>
    /// Create a new refresh token
    /// </summary>
    Task<RefreshToken> CreateAsync(RefreshToken refreshToken);

    /// <summary>
    /// Get a refresh token by its hashed value
    /// </summary>
    Task<RefreshToken?> GetByTokenHashAsync(string tokenHash);

    /// <summary>
    /// Get a refresh token by its ID
    /// </summary>
    Task<RefreshToken?> GetByIdAsync(string id);

    /// <summary>
    /// Get all active refresh tokens for a user
    /// </summary>
    Task<IEnumerable<RefreshToken>> GetActiveTokensByUserIdAsync(string userId);

    /// <summary>
    /// Get all refresh tokens for a user (including revoked/expired)
    /// </summary>
    Task<IEnumerable<RefreshToken>> GetAllByUserIdAsync(string userId);

    /// <summary>
    /// Update a refresh token
    /// </summary>
    Task UpdateAsync(RefreshToken refreshToken);

    /// <summary>
    /// Revoke a specific refresh token
    /// </summary>
    Task RevokeAsync(string tokenHash, string? replacedByTokenId = null);

    /// <summary>
    /// Revoke all refresh tokens for a user
    /// </summary>
    Task RevokeAllByUserIdAsync(string userId);

    /// <summary>
    /// Delete expired and revoked tokens older than the specified date
    /// </summary>
    Task DeleteExpiredTokensAsync(DateTime olderThan);

    /// <summary>
    /// Delete a refresh token by its ID
    /// </summary>
    Task DeleteAsync(string id);
}
