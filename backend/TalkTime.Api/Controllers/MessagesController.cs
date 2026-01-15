using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using TalkTime.Api.Hubs;
using TalkTime.Core.DTOs;
using TalkTime.Core.Entities;
using TalkTime.Core.Enums;
using TalkTime.Core.Interfaces;

namespace TalkTime.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class MessagesController : ControllerBase
{
    private readonly IMessageRepository _messageRepository;
    private readonly IConversationRepository _conversationRepository;
    private readonly IUserRepository _userRepository;
    private readonly IHubContext<TalkTimeHub> _hubContext;
    private readonly INotificationsService _notificationsService;
    private readonly ILogger<MessagesController> _logger;

    public MessagesController(
        IMessageRepository messageRepository,
        IConversationRepository conversationRepository,
        IUserRepository userRepository,
        IHubContext<TalkTimeHub> hubContext,
        INotificationsService notificationsService,
        ILogger<MessagesController> logger)
    {
        _messageRepository = messageRepository;
        _conversationRepository = conversationRepository;
        _userRepository = userRepository;
        _hubContext = hubContext;
        _notificationsService = notificationsService;
        _logger = logger;
    }

    /// <summary>
    /// Get messages for a conversation (paginated)
    /// </summary>
    [HttpGet]
    public async Task<ActionResult<MessagesResponseDto>> GetMessages(
        [FromQuery] string conversationId,
        [FromQuery] int skip = 0,
        [FromQuery] int take = 50)
    {
        try
        {
            var userId = User.FindFirst("userId")?.Value;

            if (string.IsNullOrEmpty(userId))
            {
                return Unauthorized(new { message = "User not authenticated" });
            }

            // Verify user is a participant in the conversation
            if (!await _conversationRepository.IsParticipantAsync(conversationId, userId))
            {
                return Forbid();
            }

            var messages = await _messageRepository.GetByConversationIdAsync(conversationId, skip, take);

            var messageDtos = messages.Select(m => new MessageDto(
                m.Id,
                m.ConversationId,
                new UserDto(m.Sender.Id, m.Sender.Username, m.Sender.AvatarUrl, m.Sender.Description, m.Sender.IsOnline, m.Sender.LastSeenAt),
                m.EncryptedContent,
                m.Type.ToString().ToLower(),
                m.SentAt.ToString("o")
            )).ToList();

            return Ok(new { data = messageDtos });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting messages for conversation {ConversationId}", conversationId);
            return StatusCode(500, new { message = "An error occurred" });
        }
    }

    /// <summary>
    /// Send a new message (encrypted content from frontend)
    /// </summary>
    [HttpPost]
    public async Task<ActionResult<SendMessageResponseDto>> SendMessage([FromBody] SendMessageRequest request)
    {
        try
        {
            var userId = User.FindFirst("userId")?.Value;

            if (string.IsNullOrEmpty(userId))
            {
                return Unauthorized(new { message = "User not authenticated" });
            }

            // Verify user is a participant in the conversation
            var conversation = await _conversationRepository.GetByIdWithParticipantsAsync(request.ConversationId);
            if (conversation == null)
            {
                return NotFound(new { message = "Conversation not found" });
            }

            if (!conversation.Participants.Any(p => p.UserId == userId))
            {
                return Forbid();
            }

            var sender = await _userRepository.GetByIdAsync(userId);
            if (sender == null)
            {
                return Unauthorized(new { message = "User not found" });
            }

            // Create message
            var message = new Message
            {
                Id = Guid.NewGuid().ToString(),
                ConversationId = request.ConversationId,
                SenderId = userId,
                EncryptedContent = request.Content, // Content is already encrypted by frontend
                Type = MessageType.Text,
                SentAt = DateTime.UtcNow
            };

            await _messageRepository.CreateAsync(message);

            // Get recipients (all participants except sender)
            var recipientIds = conversation.Participants
                .Where(p => p.UserId != userId)
                .Select(p => p.UserId)
                .ToList();

            // Create delivery records for offline message tracking
            if (_messageRepository is Infrastructure.Repositories.MessageRepository messageRepo)
            {
                await messageRepo.CreateDeliveryRecordsAsync(message.Id, recipientIds);
            }

            var messageDto = new MessageDto(
                message.Id,
                message.ConversationId,
                new UserDto(sender.Id, sender.Username, sender.AvatarUrl, sender.Description, sender.IsOnline, sender.LastSeenAt),
                message.EncryptedContent,
                message.Type.ToString().ToLower(),
                message.SentAt.ToString("o")
            );

            // Send real-time notification to all participants in the conversation
            try
            {
                await _hubContext.Clients.Group($"conversation_{request.ConversationId}")
                    .SendAsync("ReceiveMessage", messageDto);

                _logger.LogInformation("Message {MessageId} sent to conversation {ConversationId} by user {UserId}",
                    message.Id, request.ConversationId, userId);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to send SignalR message to conversation {ConversationId} for user {UserId}",
                    request.ConversationId, userId);
                // Continue with the operation even if SignalR fails
            }

            // Send push notifications to offline recipients
            try
            {
                foreach (var recipientId in recipientIds)
                {
                    var recipient = await _userRepository.GetByIdAsync(recipientId);
                    if (recipient != null && !recipient.IsOnline)
                    {
                        // Send push notification
                        var notificationData = System.Text.Json.JsonSerializer.Serialize(new
                        {
                            type = "message",
                            conversationId = request.ConversationId,
                            messageId = message.Id,
                            senderId = userId,
                            senderUsername = sender.Username
                        });

                        await _notificationsService.SendNotificationAsync(
                            recipientId,
                            sender.Username ?? "New message",
                            "You have a new message",
                            sender.AvatarUrl,
                            notificationData
                        );
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to send push notifications for message {MessageId}", message.Id);
                // Continue with the operation even if push notifications fail
            }

            return Ok(new { data = messageDto });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error sending message");
            return StatusCode(500, new { message = "An error occurred" });
        }
    }

    /// <summary>
    /// Get pending messages for the current user (messages sent while offline)
    /// </summary>
    [HttpGet("pending")]
    public async Task<ActionResult<MessagesResponseDto>> GetPendingMessages()
    {
        try
        {
            var userId = User.FindFirst("userId")?.Value;

            if (string.IsNullOrEmpty(userId))
            {
                return Unauthorized(new { message = "User not authenticated" });
            }

            var messages = await _messageRepository.GetPendingMessagesForUserAsync(userId);

            var messageDtos = messages.Select(m => new MessageDto(
                m.Id,
                m.ConversationId,
                new UserDto(m.Sender.Id, m.Sender.Username, m.Sender.AvatarUrl, m.Sender.Description, m.Sender.IsOnline, m.Sender.LastSeenAt),
                m.EncryptedContent,
                m.Type.ToString().ToLower(),
                m.SentAt.ToString("o")
            )).ToList();

            return Ok(new { data = messageDtos });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting pending messages");
            return StatusCode(500, new { message = "An error occurred" });
        }
    }

    /// <summary>
    /// Mark a message as delivered (called when client receives the message)
    /// </summary>
    [HttpPost("{messageId}/delivered")]
    public async Task<ActionResult> MarkAsDelivered(string messageId)
    {
        try
        {
            var userId = User.FindFirst("userId")?.Value;

            if (string.IsNullOrEmpty(userId))
            {
                return Unauthorized(new { message = "User not authenticated" });
            }

            var message = await _messageRepository.GetByIdAsync(messageId);
            if (message == null)
            {
                return NotFound(new { message = "Message not found" });
            }

            // Verify user is a participant in the conversation
            if (!await _conversationRepository.IsParticipantAsync(message.ConversationId, userId))
            {
                return Forbid();
            }

            await _messageRepository.MarkAsDeliveredAsync(messageId, userId);

            _logger.LogInformation("Message {MessageId} marked as delivered by user {UserId}", messageId, userId);

            return Ok(new { message = "Message marked as delivered" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error marking message {MessageId} as delivered", messageId);
            return StatusCode(500, new { message = "An error occurred" });
        }
    }

    /// <summary>
    /// Delete a message (only sender can delete)
    /// </summary>
    [HttpDelete("{messageId}")]
    public async Task<ActionResult> DeleteMessage(string messageId)
    {
        try
        {
            var userId = User.FindFirst("userId")?.Value;

            if (string.IsNullOrEmpty(userId))
            {
                return Unauthorized(new { message = "User not authenticated" });
            }

            var message = await _messageRepository.GetByIdAsync(messageId);
            if (message == null)
            {
                return NotFound(new { message = "Message not found" });
            }

            // Only sender can delete their message
            if (message.SenderId != userId)
            {
                return Forbid();
            }

            await _messageRepository.DeleteAsync(messageId);

            // Notify participants about message deletion
            await _hubContext.Clients.Group($"conversation_{message.ConversationId}")
                .SendAsync("MessageDeleted", new { messageId, conversationId = message.ConversationId });

            _logger.LogInformation("Message {MessageId} deleted by user {UserId}", messageId, userId);

            return Ok(new { message = "Message deleted" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting message {MessageId}", messageId);
            return StatusCode(500, new { message = "An error occurred" });
        }
    }
}
