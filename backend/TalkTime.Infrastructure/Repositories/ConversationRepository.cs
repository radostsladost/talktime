using Microsoft.EntityFrameworkCore;
using TalkTime.Core.Entities;
using TalkTime.Core.Interfaces;
using TalkTime.Infrastructure.Data;

namespace TalkTime.Infrastructure.Repositories;

public class ConversationRepository : IConversationRepository
{
    private readonly AppDbContext _context;

    public ConversationRepository(AppDbContext context)
    {
        _context = context;
    }

    public async Task<Conversation?> GetByIdAsync(string id)
    {
        return await _context.Conversations.FindAsync(id);
    }

    public async Task<Conversation?> GetByIdWithParticipantsAsync(string id)
    {
        return await _context.Conversations
            .Include(c => c.Participants)
                .ThenInclude(p => p.User)
            .Include(c => c.Messages.OrderByDescending(m => m.SentAt).Take(1))
                .ThenInclude(m => m.Sender)
            .FirstOrDefaultAsync(c => c.Id == id);
    }

    public async Task<IEnumerable<Conversation>> GetUserConversationsAsync(string userId)
    {
        return await _context.Conversations
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
        return await _context.Conversations
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
        _context.Conversations.Add(conversation);
        await _context.SaveChangesAsync();
        return conversation;
    }

    public async Task UpdateAsync(Conversation conversation)
    {
        conversation.UpdatedAt = DateTime.UtcNow;
        _context.Conversations.Update(conversation);
        await _context.SaveChangesAsync();
    }

    public async Task DeleteAsync(string id)
    {
        var conversation = await _context.Conversations.FindAsync(id);
        if (conversation != null)
        {
            _context.Conversations.Remove(conversation);
            await _context.SaveChangesAsync();
        }
    }

    public async Task AddParticipantAsync(string conversationId, string userId, bool isAdmin = false)
    {
        var participant = new ConversationParticipant
        {
            ConversationId = conversationId,
            UserId = userId,
            IsAdmin = isAdmin,
            JoinedAt = DateTime.UtcNow
        };

        _context.ConversationParticipants.Add(participant);
        await _context.SaveChangesAsync();
    }

    public async Task RemoveParticipantAsync(string conversationId, string userId)
    {
        var participant = await _context.ConversationParticipants
            .FirstOrDefaultAsync(p => p.ConversationId == conversationId && p.UserId == userId);

        if (participant != null)
        {
            _context.ConversationParticipants.Remove(participant);
            await _context.SaveChangesAsync();
        }
    }

    public async Task<bool> IsParticipantAsync(string conversationId, string userId)
    {
        return await _context.ConversationParticipants
            .AnyAsync(p => p.ConversationId == conversationId && p.UserId == userId);
    }

    public async Task<IEnumerable<string>> GetParticipantIdsAsync(string conversationId)
    {
        return await _context.ConversationParticipants
            .Where(p => p.ConversationId == conversationId)
            .Select(p => p.UserId)
            .ToListAsync();
    }
}
