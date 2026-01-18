namespace TalkTime.Core.Entities;

/// <summary>
/// Represents a reaction (emoji) on a message, like in Telegram
/// </summary>
public class Reaction
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string MessageId { get; set; } = string.Empty;
    public string UserId { get; set; } = string.Empty;

    /// <summary>
    /// The emoji character (e.g., "👍", "❤️", "😂")
    /// </summary>
    public string Emoji { get; set; } = string.Empty;

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    // Navigation properties
    public Message Message { get; set; } = null!;
    public User User { get; set; } = null!;
}
