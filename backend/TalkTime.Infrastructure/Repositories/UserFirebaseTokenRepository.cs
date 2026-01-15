using Microsoft.EntityFrameworkCore;
using TalkTime.Core.Entities;
using TalkTime.Core.Interfaces;
using TalkTime.Infrastructure.Data;

namespace TalkTime.Infrastructure.Repositories;

public class UserFirebaseTokenRepository : IUserFirebaseTokenRepository
{
    private readonly IDbContextFactory<AppDbContext> _contextFactory;

    public UserFirebaseTokenRepository(IDbContextFactory<AppDbContext> contextFactory)
    {
        _contextFactory = contextFactory;
    }

    public async Task<UserFirebaseToken> UpsertAsync(UserFirebaseToken token)
    {
        await using var context = await _contextFactory.CreateDbContextAsync();
        
        // Check if token already exists for this user and device
        var existing = await context.UserFirebaseTokens
            .FirstOrDefaultAsync(t => t.UserId == token.UserId && 
                                     (token.DeviceId == null || t.DeviceId == token.DeviceId) &&
                                     t.Token == token.Token);

        if (existing != null)
        {
            // Update existing token
            existing.Token = token.Token;
            existing.DeviceInfo = token.DeviceInfo;
            existing.LastUsedAt = DateTime.UtcNow;
            await context.SaveChangesAsync();
            return existing;
        }

        // Create new token
        context.UserFirebaseTokens.Add(token);
        await context.SaveChangesAsync();
        return token;
    }

    public async Task<List<UserFirebaseToken>> GetByUserIdAsync(string userId)
    {
        await using var context = await _contextFactory.CreateDbContextAsync();
        return await context.UserFirebaseTokens
            .Where(t => t.UserId == userId)
            .ToListAsync();
    }

    public async Task<UserFirebaseToken?> GetByTokenAsync(string token)
    {
        await using var context = await _contextFactory.CreateDbContextAsync();
        return await context.UserFirebaseTokens
            .FirstOrDefaultAsync(t => t.Token == token);
    }

    public async Task DeleteAsync(string id)
    {
        await using var context = await _contextFactory.CreateDbContextAsync();
        var token = await context.UserFirebaseTokens.FindAsync(id);
        if (token != null)
        {
            context.UserFirebaseTokens.Remove(token);
            await context.SaveChangesAsync();
        }
    }

    public async Task DeleteAllByUserIdAsync(string userId)
    {
        await using var context = await _contextFactory.CreateDbContextAsync();
        var tokens = await context.UserFirebaseTokens
            .Where(t => t.UserId == userId)
            .ToListAsync();
        
        context.UserFirebaseTokens.RemoveRange(tokens);
        await context.SaveChangesAsync();
    }

    public async Task UpdateLastUsedAsync(string token)
    {
        await using var context = await _contextFactory.CreateDbContextAsync();
        var firebaseToken = await context.UserFirebaseTokens
            .FirstOrDefaultAsync(t => t.Token == token);
        
        if (firebaseToken != null)
        {
            firebaseToken.LastUsedAt = DateTime.UtcNow;
            await context.SaveChangesAsync();
        }
    }
}
