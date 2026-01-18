namespace TalkTime.Core.Entities;

/// <summary>
/// Represents a reaction (emoji) on a message, like in Telegram.
/// Note: No FK to Message since messages are ephemeral and deleted after delivery.
/// </summary>
public class Reaction
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    
    /// <summary>
    /// Reference to the message (stored on client side, no FK constraint)
    /// </summary>
    public string MessageId { get; set; } = string.Empty;
    
    /// <summary>
    /// Conversation ID for authorization checks
    /// </summary>
    public string ConversationId { get; set; } = string.Empty;
    
    public string UserId { get; set; } = string.Empty;

    /// <summary>
    /// The emoji character (e.g., "👍", "❤️", "😂")
    /// </summary>
    public string Emoji { get; set; } = string.Empty;

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    // Navigation properties (only User, since messages are ephemeral)
    public User User { get; set; } = null!;
}
