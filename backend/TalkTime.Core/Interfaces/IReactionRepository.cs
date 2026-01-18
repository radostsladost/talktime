using TalkTime.Core.Entities;

namespace TalkTime.Core.Interfaces;

public interface IReactionRepository
{
    Task<IEnumerable<Reaction>> GetByMessageIdAsync(string messageId);
    Task<IEnumerable<Reaction>> GetByMessageIdsAsync(IEnumerable<string> messageIds);
    Task<IEnumerable<Reaction>> GetByConversationIdAsync(string conversationId);
    Task<Reaction?> GetByIdAsync(string id);
    Task<Reaction?> GetUserReactionAsync(string messageId, string userId, string emoji);
    Task<Reaction> AddAsync(Reaction reaction);
    Task RemoveAsync(string id);
    Task RemoveUserReactionAsync(string messageId, string userId, string emoji);
}
