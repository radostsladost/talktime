namespace TalkTime.Core.Entities;

public class UserFirebaseToken
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string UserId { get; set; } = string.Empty;
    public string Token { get; set; } = string.Empty;
    public string? DeviceId { get; set; }
    public string? DeviceInfo { get; set; }
    /// <summary>When true, push notification shows message content; when false, shows generic "New message".</summary>
    public bool MessagePreview { get; set; } = true;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? LastUsedAt { get; set; }

    // Navigation property
    public User? User { get; set; }
}
