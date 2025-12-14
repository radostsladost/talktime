using TalkTime.Core.Entities;

namespace TalkTime.Core.Interfaces;

public interface IConversationRepository
{
    Task<Conversation?> GetByIdAsync(string id);
    Task<Conversation?> GetByIdWithParticipantsAsync(string id);
    Task<IEnumerable<Conversation>> GetUserConversationsAsync(string userId);
    Task<Conversation?> GetDirectConversationAsync(string userId1, string userId2);
    Task<Conversation> CreateAsync(Conversation conversation);
    Task UpdateAsync(Conversation conversation);
    Task DeleteAsync(string id);
    Task AddParticipantAsync(string conversationId, string userId, bool isAdmin = false);
    Task RemoveParticipantAsync(string conversationId, string userId);
    Task<bool> IsParticipantAsync(string conversationId, string userId);
    Task<IEnumerable<string>> GetParticipantIdsAsync(string conversationId);
}
