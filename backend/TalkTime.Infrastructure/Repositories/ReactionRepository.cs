using Microsoft.EntityFrameworkCore;
using TalkTime.Core.Entities;
using TalkTime.Core.Interfaces;
using TalkTime.Infrastructure.Data;

namespace TalkTime.Infrastructure.Repositories;

public class ReactionRepository : IReactionRepository
{
    private readonly AppDbContext _context;

    public ReactionRepository(AppDbContext context)
    {
        _context = context;
    }

    public async Task<IEnumerable<Reaction>> GetByMessageIdAsync(string messageId)
    {
        return await _context.Reactions
            .Include(r => r.User)
            .Where(r => r.MessageId == messageId)
            .OrderBy(r => r.CreatedAt)
            .ToListAsync();
    }

    public async Task<IEnumerable<Reaction>> GetByMessageIdsAsync(IEnumerable<string> messageIds)
    {
        var ids = messageIds.ToList();
        return await _context.Reactions
            .Include(r => r.User)
            .Where(r => ids.Contains(r.MessageId))
            .OrderBy(r => r.CreatedAt)
            .ToListAsync();
    }

    public async Task<IEnumerable<Reaction>> GetByConversationIdAsync(string conversationId)
    {
        return await _context.Reactions
            .Include(r => r.User)
            .Where(r => r.ConversationId == conversationId)
            .OrderBy(r => r.CreatedAt)
            .ToListAsync();
    }

    public async Task<Reaction?> GetByIdAsync(string id)
    {
        return await _context.Reactions
            .Include(r => r.User)
            .FirstOrDefaultAsync(r => r.Id == id);
    }

    public async Task<Reaction?> GetUserReactionAsync(string messageId, string userId, string emoji)
    {
        return await _context.Reactions
            .FirstOrDefaultAsync(r => r.MessageId == messageId && r.UserId == userId && r.Emoji == emoji);
    }

    public async Task<Reaction> AddAsync(Reaction reaction)
    {
        _context.Reactions.Add(reaction);
        await _context.SaveChangesAsync();
        return reaction;
    }

    public async Task RemoveAsync(string id)
    {
        var reaction = await _context.Reactions.FindAsync(id);
        if (reaction != null)
        {
            _context.Reactions.Remove(reaction);
            await _context.SaveChangesAsync();
        }
    }

    public async Task RemoveUserReactionAsync(string messageId, string userId, string emoji)
    {
        var reaction = await _context.Reactions
            .FirstOrDefaultAsync(r => r.MessageId == messageId && r.UserId == userId && r.Emoji == emoji);
        
        if (reaction != null)
        {
            _context.Reactions.Remove(reaction);
            await _context.SaveChangesAsync();
        }
    }
}
