using Microsoft.EntityFrameworkCore;
using TalkTime.Core.Entities;
using TalkTime.Core.Interfaces;
using TalkTime.Infrastructure.Data;

namespace TalkTime.Infrastructure.Repositories;

public class ConversationRepository : IConversationRepository
{
    private readonly IDbContextFactory<AppDbContext> _context;

    public ConversationRepository(IDbContextFactory<AppDbContext> contextFactory)
    {
        _context = contextFactory;
    }

    public async Task<Conversation?> GetByIdAsync(string id)
    {
        await using var dbContext = _context.CreateDbContext();
        return await dbContext.Conversations.FindAsync(id);
    }

    public async Task<Conversation?> GetByIdWithParticipantsAsync(string id)
    {
        await using var dbContext = _context.CreateDbContext();
        return await dbContext.Conversations
            .Include(c => c.Participants)
                .ThenInclude(p => p.User)
            .Include(c => c.Messages.OrderByDescending(m => m.SentAt).Take(1))
                .ThenInclude(m => m.Sender)
            .FirstOrDefaultAsync(c => c.Id == id);
    }

    public async Task<IEnumerable<Conversation>> GetUserConversationsAsync(string userId)
    {
        await using var dbContext = _context.CreateDbContext();
        return await dbContext.Conversations
            .Include(c => c.Participants)
                .ThenInclude(p => p.User)
            .Include(c => c.Messages.OrderByDescending(m => m.SentAt).Take(1))
                .ThenInclude(m => m.Sender)
            .Where(c => c.Participants.Any(p => p.UserId == userId))
            .OrderByDescending(c => c.Messages.Max(m => (DateTime?)m.SentAt) ?? c.CreatedAt)
            .ToListAsync();
    }

    public async Task<Conversation?> GetDirectConversationAsync(string userId1, string userId2)
    {
        await using var dbContext = _context.CreateDbContext();
        return await dbContext.Conversations
            .Include(c => c.Participants)
                .ThenInclude(p => p.User)
            .Where(c => c.Type == Core.Enums.ConversationType.Direct)
            .Where(c => c.Participants.Count == 2)
            .Where(c => c.Participants.Any(p => p.UserId == userId1) &&
                        c.Participants.Any(p => p.UserId == userId2))
            .FirstOrDefaultAsync();
    }

    public async Task<Conversation> CreateAsync(Conversation conversation)
    {
        await using var dbContext = _context.CreateDbContext();
        dbContext.Conversations.Add(conversation);
        await dbContext.SaveChangesAsync();
        return conversation;
    }

    public async Task UpdateAsync(Conversation conversation)
    {
        await using var dbContext = _context.CreateDbContext();
        conversation.UpdatedAt = DateTime.UtcNow;
        dbContext.Conversations.Update(conversation);
        await dbContext.SaveChangesAsync();
    }

    public async Task DeleteAsync(string id)
    {
        await using var dbContext = _context.CreateDbContext();
        var conversation = await dbContext.Conversations.FindAsync(id);
        if (conversation != null)
        {
            dbContext.Conversations.Remove(conversation);
            await dbContext.SaveChangesAsync();
        }
    }

    public async Task AddParticipantAsync(string conversationId, string userId, bool isAdmin = false)
    {
        await using var dbContext = _context.CreateDbContext();
        var participant = new ConversationParticipant
        {
            ConversationId = conversationId,
            UserId = userId,
            IsAdmin = isAdmin,
            JoinedAt = DateTime.UtcNow
        };

        dbContext.ConversationParticipants.Add(participant);
        await dbContext.SaveChangesAsync();
    }

    public async Task RemoveParticipantAsync(string conversationId, string userId)
    {
        await using var dbContext = _context.CreateDbContext();
        var participant = await dbContext.ConversationParticipants
            .FirstOrDefaultAsync(p => p.ConversationId == conversationId && p.UserId == userId);

        if (participant != null)
        {
            dbContext.ConversationParticipants.Remove(participant);
            await dbContext.SaveChangesAsync();
        }
    }

    public async Task<bool> IsParticipantAsync(string conversationId, string userId)
    {
        await using var dbContext = _context.CreateDbContext();
        return await dbContext.ConversationParticipants
            .AnyAsync(p => p.ConversationId == conversationId && p.UserId == userId);
    }

    public async Task<IEnumerable<string>> GetParticipantIdsAsync(string conversationId)
    {
        await using var dbContext = _context.CreateDbContext();
        return await dbContext.ConversationParticipants
            .Where(p => p.ConversationId == conversationId)
            .Select(p => p.UserId)
            .ToListAsync();
    }
}
