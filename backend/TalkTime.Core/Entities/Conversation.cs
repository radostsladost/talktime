using TalkTime.Core.Enums;

namespace TalkTime.Core.Entities;

public class Conversation
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public ConversationType Type { get; set; }
    public string? Name { get; set; } // Null for direct messages, set for groups
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? UpdatedAt { get; set; }

    // Navigation properties
    public ICollection<ConversationParticipant> Participants { get; set; } = new List<ConversationParticipant>();
    public ICollection<Message> Messages { get; set; } = new List<Message>();
}
