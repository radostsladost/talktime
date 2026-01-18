using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using TalkTime.Api.Hubs;
using TalkTime.Core.DTOs;
using TalkTime.Core.Entities;
using TalkTime.Core.Interfaces;

namespace TalkTime.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class ReactionsController : ControllerBase
{
    private readonly IReactionRepository _reactionRepository;
    private readonly IMessageRepository _messageRepository;
    private readonly IConversationRepository _conversationRepository;
    private readonly IUserRepository _userRepository;
    private readonly IHubContext<TalkTimeHub> _hubContext;
    private readonly ILogger<ReactionsController> _logger;

    public ReactionsController(
        IReactionRepository reactionRepository,
        IMessageRepository messageRepository,
        IConversationRepository conversationRepository,
        IUserRepository userRepository,
        IHubContext<TalkTimeHub> hubContext,
        ILogger<ReactionsController> logger)
    {
        _reactionRepository = reactionRepository;
        _messageRepository = messageRepository;
        _conversationRepository = conversationRepository;
        _userRepository = userRepository;
        _hubContext = hubContext;
        _logger = logger;
    }

    /// <summary>
    /// Get reactions for a message
    /// </summary>
    [HttpGet("{messageId}")]
    public async Task<ActionResult<IEnumerable<ReactionDto>>> GetReactions(string messageId, string conversationId)
    {
        try
        {
            var userId = User.FindFirst("userId")?.Value;
            if (string.IsNullOrEmpty(userId))
            {
                return Unauthorized(new { message = "User not authenticated" });
            }

            // var message = await _messageRepository.GetByIdAsync(messageId);
            // if (message == null)
            // {
            //     return NotFound(new { message = "Message not found" });
            // }

            // Verify user is a participant in the conversation
            if (!await _conversationRepository.IsParticipantAsync(conversationId, userId))
            {
                return Forbid();
            }

            var reactions = await _reactionRepository.GetByMessageIdAsync(messageId);
            var reactionDtos = reactions.Select(r => new ReactionDto(
                r.Id,
                r.Emoji,
                r.UserId,
                r.User.Username
            )).ToList();

            return Ok(new { data = reactionDtos });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting reactions for message {MessageId}", messageId);
            return StatusCode(500, new { message = "An error occurred" });
        }
    }

    /// <summary>
    /// Get reactions for multiple messages (batch)
    /// </summary>
    [HttpGet("batch")]
    public async Task<ActionResult<Dictionary<string, List<ReactionDto>>>> GetReactionsBatch(
        [FromQuery] string conversationId,
        [FromQuery] string messageIds)
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

            var ids = messageIds.Split(',').Where(id => !string.IsNullOrWhiteSpace(id)).ToList();
            var reactions = await _reactionRepository.GetByMessageIdsAsync(ids);
            
            // Group reactions by messageId
            var grouped = reactions
                .GroupBy(r => r.MessageId)
                .ToDictionary(
                    g => g.Key,
                    g => g.Select(r => new ReactionDto(r.Id, r.Emoji, r.UserId, r.User.Username)).ToList()
                );

            return Ok(new { data = grouped });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting reactions batch");
            return StatusCode(500, new { message = "An error occurred" });
        }
    }

    /// <summary>
    /// Add a reaction to a message
    /// </summary>
    [HttpPost]
    public async Task<ActionResult<ReactionDto>> AddReaction([FromBody] AddReactionRequest request)
    {
        try
        {
            var userId = User.FindFirst("userId")?.Value;
            if (string.IsNullOrEmpty(userId))
            {
                return Unauthorized(new { message = "User not authenticated" });
            }

            // var message = await _messageRepository.GetByIdAsync(request.MessageId);
            // if (message == null)
            // {
            //     return NotFound(new { message = "Message not found" });
            // }

            // Verify user is a participant in the conversation
            if (!await _conversationRepository.IsParticipantAsync(request.ConversationId, userId))
            {
                return Forbid();
            }

            // Check if user already has this reaction
            var existingReaction = await _reactionRepository.GetUserReactionAsync(
                request.MessageId, userId, request.Emoji);

            if (existingReaction != null)
            {
                return BadRequest(new { message = "You already reacted with this emoji" });
            }

            var user = await _userRepository.GetByIdAsync(userId);
            if (user == null)
            {
                return Unauthorized(new { message = "User not found" });
            }

            var reaction = new Reaction
            {
                Id = Guid.NewGuid().ToString(),
                MessageId = request.MessageId,
                ConversationId = request.ConversationId,
                UserId = userId,
                Emoji = request.Emoji,
                CreatedAt = DateTime.UtcNow
            };

            await _reactionRepository.AddAsync(reaction);

            var reactionDto = new ReactionDto(
                reaction.Id,
                reaction.Emoji,
                reaction.UserId,
                user.Username
            );

            // Notify all participants in the conversation about the new reaction
            await _hubContext.Clients.Group($"conversation_{request.ConversationId}")
                .SendAsync("ReactionAdded", new
                {
                    messageId = request.MessageId,
                    conversationId = request.ConversationId,
                    reaction = reactionDto
                });

            _logger.LogInformation("Reaction {Emoji} added to message {MessageId} by user {UserId}",
                request.Emoji, request.MessageId, userId);

            return Ok(new { data = reactionDto });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error adding reaction to message {MessageId}", request.MessageId);
            return StatusCode(500, new { message = "An error occurred" });
        }
    }

    /// <summary>
    /// Remove a reaction from a message
    /// </summary>
    [HttpDelete]
    public async Task<ActionResult> RemoveReaction([FromBody] RemoveReactionRequest request)
    {
        try
        {
            var userId = User.FindFirst("userId")?.Value;
            if (string.IsNullOrEmpty(userId))
            {
                return Unauthorized(new { message = "User not authenticated" });
            }

            // var message = await _messageRepository.GetByIdAsync(request.MessageId);
            // if (message == null)
            // {
            //     return NotFound(new { message = "Message not found" });
            // }

            // Verify user is a participant in the conversation
            if (!await _conversationRepository.IsParticipantAsync(request.ConversationId, userId))
            {
                return Forbid();
            }

            // Remove the reaction
            await _reactionRepository.RemoveUserReactionAsync(request.MessageId, userId, request.Emoji);

            // Notify all participants in the conversation about the removed reaction
            await _hubContext.Clients.Group($"conversation_{request.ConversationId}")
                .SendAsync("ReactionRemoved", new
                {
                    messageId = request.MessageId,
                    conversationId = request.ConversationId,
                    emoji = request.Emoji,
                    userId = userId
                });

            _logger.LogInformation("Reaction {Emoji} removed from message {MessageId} by user {UserId}",
                request.Emoji, request.MessageId, userId);

            return Ok(new { message = "Reaction removed" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error removing reaction from message {MessageId}", request.MessageId);
            return StatusCode(500, new { message = "An error occurred" });
        }
    }
}
