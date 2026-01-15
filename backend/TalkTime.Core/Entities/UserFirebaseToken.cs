namespace TalkTime.Core.Entities;

public class UserFirebaseToken
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string UserId { get; set; } = string.Empty;
    public string Token { get; set; } = string.Empty;
    public string? DeviceId { get; set; }
    public string? DeviceInfo { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? LastUsedAt { get; set; }

    // Navigation property
    public User? User { get; set; }
}
