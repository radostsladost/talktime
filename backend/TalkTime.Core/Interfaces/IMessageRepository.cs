using TalkTime.Core.Entities;

namespace TalkTime.Core.Interfaces;

public interface IMessageRepository
{
    Task<Message?> GetByIdAsync(string id);
    Task<IEnumerable<Message>> GetByConversationIdAsync(string conversationId, int skip = 0, int take = 50);
    Task<IEnumerable<Message>> GetPendingMessagesForUserAsync(string userId);
    Task<Message> CreateAsync(Message message);
    Task UpdateAsync(Message message);
    Task DeleteAsync(string id);
    Task MarkAsDeliveredAsync(string messageId, string recipientId);
    Task DeleteDeliveredMessagesAsync();
}
