using Microsoft.EntityFrameworkCore;
using TalkTime.Core.Entities;
using TalkTime.Core.Interfaces;
using TalkTime.Infrastructure.Data;

namespace TalkTime.Infrastructure.Repositories;

public class RefreshTokenRepository : IRefreshTokenRepository
{
    private readonly IDbContextFactory<AppDbContext> _contextFactory;

    public RefreshTokenRepository(IDbContextFactory<AppDbContext> contextFactory)
    {
        _contextFactory = contextFactory;
    }

    public async Task<RefreshToken> CreateAsync(RefreshToken refreshToken)
    {
        await using var context = await _contextFactory.CreateDbContextAsync();
        context.RefreshTokens.Add(refreshToken);
        await context.SaveChangesAsync();
        return refreshToken;
    }

    public async Task<RefreshToken?> GetByTokenHashAsync(string tokenHash)
    {
        await using var context = await _contextFactory.CreateDbContextAsync();
        return await context.RefreshTokens
            .Include(rt => rt.User)
            .FirstOrDefaultAsync(rt => rt.TokenHash == tokenHash);
    }

    public async Task<RefreshToken?> GetByIdAsync(string id)
    {
        await using var context = await _contextFactory.CreateDbContextAsync();
        return await context.RefreshTokens
            .Include(rt => rt.User)
            .FirstOrDefaultAsync(rt => rt.Id == id);
    }

    public async Task<IEnumerable<RefreshToken>> GetActiveTokensByUserIdAsync(string userId)
    {
        await using var context = await _contextFactory.CreateDbContextAsync();
        var now = DateTime.UtcNow;
        return await context.RefreshTokens
            .Where(rt => rt.UserId == userId && rt.RevokedAt == null && rt.ExpiresAt > now)
            .OrderByDescending(rt => rt.CreatedAt)
            .ToListAsync();
    }

    public async Task<IEnumerable<RefreshToken>> GetAllByUserIdAsync(string userId)
    {
        await using var context = await _contextFactory.CreateDbContextAsync();
        return await context.RefreshTokens
            .Where(rt => rt.UserId == userId)
            .OrderByDescending(rt => rt.CreatedAt)
            .ToListAsync();
    }

    public async Task UpdateAsync(RefreshToken refreshToken)
    {
        await using var context = await _contextFactory.CreateDbContextAsync();
        context.RefreshTokens.Update(refreshToken);
        await context.SaveChangesAsync();
    }

    public async Task RevokeAsync(string tokenHash, string? replacedByTokenId = null)
    {
        await using var context = await _contextFactory.CreateDbContextAsync();
        var token = await context.RefreshTokens
            .FirstOrDefaultAsync(rt => rt.TokenHash == tokenHash);

        if (token != null)
        {
            token.RevokedAt = DateTime.UtcNow;
            token.ReplacedByTokenId = replacedByTokenId;
            await context.SaveChangesAsync();
        }
    }

    public async Task RevokeAllByUserIdAsync(string userId)
    {
        await using var context = await _contextFactory.CreateDbContextAsync();
        var tokens = await context.RefreshTokens
            .Where(rt => rt.UserId == userId && rt.RevokedAt == null)
            .ToListAsync();

        foreach (var token in tokens)
        {
            token.RevokedAt = DateTime.UtcNow;
        }

        await context.SaveChangesAsync();
    }

    public async Task DeleteExpiredTokensAsync(DateTime olderThan)
    {
        await using var context = await _contextFactory.CreateDbContextAsync();
        var tokensToDelete = await context.RefreshTokens
            .Where(rt => (rt.ExpiresAt < DateTime.UtcNow || rt.RevokedAt != null) && rt.CreatedAt < olderThan)
            .ToListAsync();

        context.RefreshTokens.RemoveRange(tokensToDelete);
        await context.SaveChangesAsync();
    }

    public async Task DeleteAsync(string id)
    {
        await using var context = await _contextFactory.CreateDbContextAsync();
        var token = await context.RefreshTokens.FindAsync(id);

        if (token != null)
        {
            context.RefreshTokens.Remove(token);
            await context.SaveChangesAsync();
        }
    }
}
