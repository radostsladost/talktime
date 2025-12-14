using Microsoft.EntityFrameworkCore;
using TalkTime.Core.Entities;
using TalkTime.Core.Interfaces;
using TalkTime.Infrastructure.Data;

namespace TalkTime.Infrastructure.Repositories;

public class MessageRepository : IMessageRepository
{
    private readonly AppDbContext _context;

    public MessageRepository(AppDbContext context)
    {
        _context = context;
    }

    public async Task<Message?> GetByIdAsync(string id)
    {
        return await _context.Messages
            .Include(m => m.Sender)
            .Include(m => m.Deliveries)
            .FirstOrDefaultAsync(m => m.Id == id);
    }

    public async Task<IEnumerable<Message>> GetByConversationIdAsync(string conversationId, int skip = 0, int take = 50)
    {
        return await _context.Messages
            .Include(m => m.Sender)
            .Where(m => m.ConversationId == conversationId)
            .OrderByDescending(m => m.SentAt)
            .Skip(skip)
            .Take(take)
            .ToListAsync();
    }

    public async Task<IEnumerable<Message>> GetPendingMessagesForUserAsync(string userId)
    {
        // Get messages where this user is a recipient but hasn't received them yet
        return await _context.Messages
            .Include(m => m.Sender)
            .Include(m => m.Deliveries)
            .Where(m => m.Deliveries.Any(d => d.RecipientId == userId && !d.IsDelivered))
            .OrderBy(m => m.SentAt)
            .ToListAsync();
    }

    public async Task<Message> CreateAsync(Message message)
    {
        _context.Messages.Add(message);
        await _context.SaveChangesAsync();
        return message;
    }

    public async Task UpdateAsync(Message message)
    {
        _context.Messages.Update(message);
        await _context.SaveChangesAsync();
    }

    public async Task DeleteAsync(string id)
    {
        var message = await _context.Messages.FindAsync(id);
        if (message != null)
        {
            _context.Messages.Remove(message);
            await _context.SaveChangesAsync();
        }
    }

    public async Task MarkAsDeliveredAsync(string messageId, string recipientId)
    {
        var delivery = await _context.MessageDeliveries
            .FirstOrDefaultAsync(d => d.MessageId == messageId && d.RecipientId == recipientId);

        if (delivery != null && !delivery.IsDelivered)
        {
            delivery.IsDelivered = true;
            delivery.DeliveredAt = DateTime.UtcNow;
            await _context.SaveChangesAsync();

            // Check if all recipients have received the message
            await TryDeleteFullyDeliveredMessageAsync(messageId);
        }
    }

    public async Task DeleteDeliveredMessagesAsync()
    {
        // Find messages where all deliveries are marked as delivered
        var fullyDeliveredMessages = await _context.Messages
            .Include(m => m.Deliveries)
            .Where(m => m.Deliveries.All(d => d.IsDelivered))
            .ToListAsync();

        if (fullyDeliveredMessages.Any())
        {
            _context.Messages.RemoveRange(fullyDeliveredMessages);
            await _context.SaveChangesAsync();
        }
    }

    /// <summary>
    /// Creates delivery records for all participants in the conversation (except sender)
    /// </summary>
    public async Task CreateDeliveryRecordsAsync(string messageId, IEnumerable<string> recipientIds)
    {
        var deliveries = recipientIds.Select(recipientId => new MessageDelivery
        {
            MessageId = messageId,
            RecipientId = recipientId,
            IsDelivered = false
        });

        _context.MessageDeliveries.AddRange(deliveries);
        await _context.SaveChangesAsync();
    }

    /// <summary>
    /// Check if all recipients have received the message and delete it if so
    /// </summary>
    private async Task TryDeleteFullyDeliveredMessageAsync(string messageId)
    {
        var message = await _context.Messages
            .Include(m => m.Deliveries)
            .FirstOrDefaultAsync(m => m.Id == messageId);

        if (message != null && message.Deliveries.All(d => d.IsDelivered))
        {
            _context.Messages.Remove(message);
            await _context.SaveChangesAsync();
        }
    }
}
