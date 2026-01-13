using Microsoft.EntityFrameworkCore;
using TalkTime.Core.Entities;
using TalkTime.Core.Interfaces;
using TalkTime.Infrastructure.Data;

namespace TalkTime.Infrastructure.Repositories;

public class UserRepository : IUserRepository
{
    private readonly IDbContextFactory<AppDbContext> _context;

    public UserRepository(IDbContextFactory<AppDbContext> contextFactory)
    {
        _context = contextFactory;
    }

    public async Task<User?> GetByIdAsync(string id)
    {
        await using var dbContext = _context.CreateDbContext();
        return await dbContext.Users.FindAsync(id);
    }

    public async Task<User?> GetByEmailAsync(string email)
    {
        await using var dbContext = _context.CreateDbContext();
        return await dbContext.Users
            .FirstOrDefaultAsync(u => u.Email.ToLower() == email.ToLower());
    }

    public async Task<User?> GetByUsernameAsync(string username)
    {
        await using var dbContext = _context.CreateDbContext();
        return await dbContext.Users
            .FirstOrDefaultAsync(u => u.Username.Contains(username, StringComparison.InvariantCultureIgnoreCase));
    }

    public async Task<List<User>> GetAllAsync()
    {
        await using var dbContext = _context.CreateDbContext();
        return await dbContext.Users.ToListAsync();
    }

    public async Task<List<User>> GetByIdsAsync(IEnumerable<string> ids)
    {
        await using var dbContext = _context.CreateDbContext();
        return await dbContext.Users
            .Where(u => ids.Contains(u.Id))
            .ToListAsync();
    }

    public async Task<List<User>> SearchAsync(string query, int limit = 20)
    {
        await using var dbContext = _context.CreateDbContext();
        var lowerQuery = query.ToLower();
        return await dbContext.Users
            .Where(u => u.Username.ToLower().Contains(lowerQuery) ||
                        u.Email.ToLower().Contains(lowerQuery))
            .Take(limit)
            .ToListAsync();
    }

    public async Task<User> CreateAsync(User user)
    {
        await using var dbContext = _context.CreateDbContext();
        dbContext.Users.Add(user);
        await dbContext.SaveChangesAsync();
        return user;
    }

    public async Task<User> UpdateAsync(User user)
    {
        await using var dbContext = _context.CreateDbContext();
        dbContext.Users.Update(user);
        await dbContext.SaveChangesAsync();
        return user;
    }

    public async Task DeleteAsync(string id)
    {
        await using var dbContext = _context.CreateDbContext();
        var user = await dbContext.Users.FindAsync(id);
        if (user != null)
        {
            dbContext.Users.Remove(user);
            await dbContext.SaveChangesAsync();
        }
    }

    public async Task SetOnlineStatusAsync(string userId, bool isOnline)
    {
        await using var dbContext = _context.CreateDbContext();
        var user = await dbContext.Users.FindAsync(userId);
        if (user != null)
        {
            user.IsOnline = isOnline;
            user.LastSeenAt = isOnline ? null : DateTime.UtcNow;
            await dbContext.SaveChangesAsync();
        }
    }

    public async Task<bool> ExistsAsync(string id)
    {
        await using var dbContext = _context.CreateDbContext();
        return await dbContext.Users.AnyAsync(u => u.Id == id);
    }

    public async Task<bool> EmailExistsAsync(string email)
    {
        await using var dbContext = _context.CreateDbContext();
        return await dbContext.Users.AnyAsync(u => u.Email.ToLower() == email.ToLower());
    }

    public async Task<bool> UsernameExistsAsync(string username)
    {
        await using var dbContext = _context.CreateDbContext();
        return await dbContext.Users.AnyAsync(u => u.Username.ToLower() == username.ToLower());
    }
}
