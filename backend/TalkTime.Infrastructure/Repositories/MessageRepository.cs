using Microsoft.EntityFrameworkCore;
using TalkTime.Core.Entities;
using TalkTime.Core.Interfaces;
using TalkTime.Infrastructure.Data;

namespace TalkTime.Infrastructure.Repositories;

public class MessageRepository : IMessageRepository
{
    private readonly IDbContextFactory<AppDbContext> _context;

    public MessageRepository(IDbContextFactory<AppDbContext> contextFactory)
    {
        _context = contextFactory;
    }

    public async Task<Message?> GetByIdAsync(string id)
    {
        await using var dbContext = _context.CreateDbContext();
        return await dbContext.Messages
                  .Include(m => m.Sender)
                  .Include(m => m.Deliveries)
                  .FirstOrDefaultAsync(m => m.Id == id);
    }

    public async Task<IEnumerable<Message>> GetByConversationIdAsync(string conversationId, int skip = 0, int take = 50)
    {
        await using var dbContext = _context.CreateDbContext();
        return await dbContext.Messages
            .Include(m => m.Sender)
            .Where(m => m.ConversationId == conversationId)
            .OrderByDescending(m => m.SentAt)
            .Skip(skip)
            .Take(take)
            .ToListAsync();
    }

    public async Task<IEnumerable<Message>> GetPendingMessagesForUserAsync(string userId)
    {
        await using var dbContext = _context.CreateDbContext();
        // Get messages where this user is a recipient but hasn't received them yet
        return await dbContext.Messages
            .Include(m => m.Sender)
            .Include(m => m.Deliveries)
            .Where(m => m.Deliveries.Any(d => d.RecipientId == userId && !d.IsDelivered))
            .OrderBy(m => m.SentAt)
            .ToListAsync();
    }

    public async Task<Message> CreateAsync(Message message)
    {
        await using var dbContext = _context.CreateDbContext();
        dbContext.Messages.Add(message);
        await dbContext.SaveChangesAsync();
        return message;
    }

    public async Task UpdateAsync(Message message)
    {
        await using var dbContext = _context.CreateDbContext();
        dbContext.Messages.Update(message);
        await dbContext.SaveChangesAsync();
    }

    public async Task DeleteAsync(string id)
    {
        await using var dbContext = _context.CreateDbContext();
        var message = await dbContext.Messages.FindAsync(id);
        if (message != null)
        {
            dbContext.Messages.Remove(message);
            await dbContext.SaveChangesAsync();
        }
    }

    public async Task MarkAsDeliveredAsync(string messageId, string recipientId)
    {
        await using var dbContext = _context.CreateDbContext();
        var delivery = await dbContext.MessageDeliveries
            .FirstOrDefaultAsync(d => d.MessageId == messageId && d.RecipientId == recipientId);

        if (delivery != null && !delivery.IsDelivered)
        {
            delivery.IsDelivered = true;
            delivery.DeliveredAt = DateTime.UtcNow;
            await dbContext.SaveChangesAsync();

            // Check if all recipients have received the message
            await TryDeleteFullyDeliveredMessageAsync(messageId);
        }
    }

    public async Task DeleteDeliveredMessagesAsync()
    {
        await using var dbContext = _context.CreateDbContext();
        // Find messages where all deliveries are marked as delivered
        var fullyDeliveredMessages = await dbContext.Messages
            .Include(m => m.Deliveries)
            .Where(m => m.Deliveries.All(d => d.IsDelivered))
            .ToListAsync();

        if (fullyDeliveredMessages.Any())
        {
            dbContext.Messages.RemoveRange(fullyDeliveredMessages);
            await dbContext.SaveChangesAsync();
        }
    }

    /// <summary>
    /// Creates delivery records for all participants in the conversation (except sender)
    /// </summary>
    public async Task CreateDeliveryRecordsAsync(string messageId, IEnumerable<string> recipientIds)
    {
        await using var dbContext = _context.CreateDbContext();
        var deliveries = recipientIds.Select(recipientId => new MessageDelivery
        {
            MessageId = messageId,
            RecipientId = recipientId,
            IsDelivered = false
        });

        dbContext.MessageDeliveries.AddRange(deliveries);
        await dbContext.SaveChangesAsync();
    }

    /// <summary>
    /// Check if all recipients have received the message and delete it if so
    /// </summary>
    private async Task TryDeleteFullyDeliveredMessageAsync(string messageId)
    {
        await using var dbContext = _context.CreateDbContext();
        var message = await dbContext.Messages
            .Include(m => m.Deliveries)
            .FirstOrDefaultAsync(m => m.Id == messageId);

        if (message != null && message.Deliveries.All(d => d.IsDelivered))
        {
            dbContext.Messages.Remove(message);
            await dbContext.SaveChangesAsync();
        }
    }
}
