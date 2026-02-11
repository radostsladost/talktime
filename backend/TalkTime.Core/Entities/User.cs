namespace TalkTime.Core.Entities;

public class User
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Username { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string PasswordHash { get; set; } = string.Empty;
    /// <summary>Number of consecutive failed login attempts within the current 5-minute window.</summary>
    public int WrongPasswordsCount { get; set; }
    /// <summary>Start of the current failure window (first wrong attempt). Used to reset count after 5 minutes.</summary>
    public DateTime? WrongPasswordDate { get; set; }
    public string? AvatarUrl { get; set; }
    public string? Description { get; set; }
    public bool IsOnline { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? LastSeenAt { get; set; }

    // Navigation properties
    public ICollection<ConversationParticipant> ConversationParticipants { get; set; } = new List<ConversationParticipant>();
    public ICollection<Message> SentMessages { get; set; } = new List<Message>();
}
