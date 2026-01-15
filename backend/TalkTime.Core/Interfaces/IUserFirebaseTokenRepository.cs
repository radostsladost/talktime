using TalkTime.Core.Entities;

namespace TalkTime.Core.Interfaces;

public interface IUserFirebaseTokenRepository
{
    /// <summary>
    /// Create or update a Firebase token for a user
    /// </summary>
    Task<UserFirebaseToken> UpsertAsync(UserFirebaseToken token);

    /// <summary>
    /// Get all active Firebase tokens for a user
    /// </summary>
    Task<List<UserFirebaseToken>> GetByUserIdAsync(string userId);

    /// <summary>
    /// Get a Firebase token by token value
    /// </summary>
    Task<UserFirebaseToken?> GetByTokenAsync(string token);

    /// <summary>
    /// Delete a Firebase token
    /// </summary>
    Task DeleteAsync(string id);

    /// <summary>
    /// Delete all tokens for a user
    /// </summary>
    Task DeleteAllByUserIdAsync(string userId);

    /// <summary>
    /// Update last used timestamp
    /// </summary>
    Task UpdateLastUsedAsync(string token);
}
