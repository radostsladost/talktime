using TalkTime.Core.Enums;

namespace TalkTime.Core.Entities;

public class Message
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string ConversationId { get; set; } = string.Empty;
    public string SenderId { get; set; } = string.Empty;

    /// <summary>
    /// Encrypted content from the frontend. Server stores but cannot read.
    /// </summary>
    public string EncryptedContent { get; set; } = string.Empty;

    public MessageType Type { get; set; } = MessageType.Text;
    public DateTime SentAt { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// Tracks which users have received this message.
    /// Message is deleted from DB once all recipients have received it.
    /// </summary>
    public ICollection<MessageDelivery> Deliveries { get; set; } = new List<MessageDelivery>();

    // Navigation properties
    public Conversation Conversation { get; set; } = null!;
    public User Sender { get; set; } = null!;
}

/// <summary>
/// Tracks message delivery status per recipient.
/// </summary>
public class MessageDelivery
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string MessageId { get; set; } = string.Empty;
    public string RecipientId { get; set; } = string.Empty;
    public bool IsDelivered { get; set; }
    public DateTime? DeliveredAt { get; set; }

    // Navigation properties
    public Message Message { get; set; } = null!;
    public User Recipient { get; set; } = null!;
}
