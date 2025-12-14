namespace TalkTime.Core.Entities;

public class ConversationParticipant
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string UserId { get; set; } = string.Empty;
    public string ConversationId { get; set; } = string.Empty;
    public DateTime JoinedAt { get; set; } = DateTime.UtcNow;
    public bool IsAdmin { get; set; }

    // Navigation properties
    public User User { get; set; } = null!;
    public Conversation Conversation { get; set; } = null!;
}
