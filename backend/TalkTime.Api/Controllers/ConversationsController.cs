using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TalkTime.Core.DTOs;
using TalkTime.Core.Entities;
using TalkTime.Core.Enums;
using TalkTime.Core.Interfaces;

namespace TalkTime.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class ConversationsController : ControllerBase
{
    private readonly IConversationRepository _conversationRepository;
    private readonly IUserRepository _userRepository;
    private readonly ILogger<ConversationsController> _logger;

    public ConversationsController(
        IConversationRepository conversationRepository,
        IUserRepository userRepository,
        ILogger<ConversationsController> logger)
    {
        _conversationRepository = conversationRepository;
        _userRepository = userRepository;
        _logger = logger;
    }

    [HttpGet]
    public async Task<ActionResult<ConversationsResponseDto>> GetConversations()
    {
        try
        {
            var userId = User.FindFirst("userId")?.Value;

            if (string.IsNullOrEmpty(userId))
            {
                return Unauthorized(new { message = "User not authenticated" });
            }

            var conversations = await _conversationRepository.GetUserConversationsAsync(userId);

            var conversationDtos = conversations.Select(c => new ConversationDto(
                c.Id,
                c.Type.ToString().ToLower(),
                c.Name,
                c.Participants.Select(p => new UserDto(
                    p.User.Id,
                    p.User.Username,
                    p.User.AvatarUrl
                )).ToList(),
                c.Messages.FirstOrDefault()?.EncryptedContent,
                c.Messages.FirstOrDefault()?.SentAt.ToString("o")
            )).ToList();

            return Ok(new { data = conversationDtos });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting conversations");
            return StatusCode(500, new { message = "An error occurred" });
        }
    }

    [HttpGet("{id}")]
    public async Task<ActionResult<ConversationDetailDto>> GetConversation(string id)
    {
        try
        {
            var userId = User.FindFirst("userId")?.Value;

            if (string.IsNullOrEmpty(userId))
            {
                return Unauthorized(new { message = "User not authenticated" });
            }

            var conversation = await _conversationRepository.GetByIdWithParticipantsAsync(id);

            if (conversation == null)
            {
                return NotFound(new { message = "Conversation not found" });
            }

            // Check if user is a participant
            if (!conversation.Participants.Any(p => p.UserId == userId))
            {
                return Forbid();
            }

            return Ok(new
            {
                data = new ConversationDetailDto(
                    conversation.Id,
                    conversation.Type.ToString().ToLower(),
                    conversation.Name,
                    conversation.Participants.Select(p => new UserDto(
                        p.User.Id,
                        p.User.Username,
                        p.User.AvatarUrl
                    )).ToList(),
                    conversation.CreatedAt
                )
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting conversation {ConversationId}", id);
            return StatusCode(500, new { message = "An error occurred" });
        }
    }

    [HttpPost]
    public async Task<ActionResult<ConversationDto>> CreateConversation([FromBody] CreateConversationRequest request)
    {
        try
        {
            var userId = User.FindFirst("userId")?.Value;

            if (string.IsNullOrEmpty(userId))
            {
                return Unauthorized(new { message = "User not authenticated" });
            }

            var type = request.Type.ToLower() == "group"
                ? ConversationType.Group
                : ConversationType.Direct;

            // For direct conversations, check if one already exists
            if (type == ConversationType.Direct && request.ParticipantIds.Count == 1)
            {
                var existingConversation = await _conversationRepository.GetDirectConversationAsync(
                    userId, request.ParticipantIds[0]);

                if (existingConversation != null)
                {
                    return Ok(new
                    {
                        data = new ConversationDto(
                            existingConversation.Id,
                            existingConversation.Type.ToString().ToLower(),
                            existingConversation.Name,
                            existingConversation.Participants.Select(p => new UserDto(
                                p.User.Id,
                                p.User.Username,
                                p.User.AvatarUrl
                            )).ToList(),
                            null,
                            null
                        )
                    });
                }
            }

            // Validate participants exist
            var allParticipantIds = request.ParticipantIds.Concat(new[] { userId }).Distinct().ToList();
            var users = await _userRepository.GetByIdsAsync(allParticipantIds);

            if (users.Count != allParticipantIds.Count)
            {
                return BadRequest(new { message = "One or more participants not found" });
            }

            // Create conversation
            var conversation = new Conversation
            {
                Id = Guid.NewGuid().ToString(),
                Type = type,
                Name = type == ConversationType.Group ? request.Name : null,
                CreatedAt = DateTime.UtcNow
            };

            await _conversationRepository.CreateAsync(conversation);

            // Add participants
            foreach (var participantId in allParticipantIds)
            {
                var isAdmin = participantId == userId && type == ConversationType.Group;
                await _conversationRepository.AddParticipantAsync(conversation.Id, participantId, isAdmin);
            }

            // Fetch the created conversation with participants
            var createdConversation = await _conversationRepository.GetByIdWithParticipantsAsync(conversation.Id);

            _logger.LogInformation("Conversation {ConversationId} created by user {UserId}", conversation.Id, userId);

            return CreatedAtAction(
                nameof(GetConversation),
                new { id = conversation.Id },
                new
                {
                    data = new ConversationDto(
                        createdConversation!.Id,
                        createdConversation.Type.ToString().ToLower(),
                        createdConversation.Name,
                        createdConversation.Participants.Select(p => new UserDto(
                            p.User.Id,
                            p.User.Username,
                            p.User.AvatarUrl
                        )).ToList(),
                        null,
                        null
                    )
                });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating conversation");
            return StatusCode(500, new { message = "An error occurred" });
        }
    }

    [HttpPut("{id}")]
    public async Task<ActionResult> UpdateConversation(string id, [FromBody] UpdateConversationRequest request)
    {
        try
        {
            var userId = User.FindFirst("userId")?.Value;

            if (string.IsNullOrEmpty(userId))
            {
                return Unauthorized(new { message = "User not authenticated" });
            }

            var conversation = await _conversationRepository.GetByIdWithParticipantsAsync(id);

            if (conversation == null)
            {
                return NotFound(new { message = "Conversation not found" });
            }

            // Check if user is a participant (and admin for groups)
            var participant = conversation.Participants.FirstOrDefault(p => p.UserId == userId);
            if (participant == null)
            {
                return Forbid();
            }

            if (conversation.Type == ConversationType.Group && !participant.IsAdmin)
            {
                return Forbid();
            }

            // Update conversation
            if (request.Name != null)
            {
                conversation.Name = request.Name;
            }

            await _conversationRepository.UpdateAsync(conversation);

            _logger.LogInformation("Conversation {ConversationId} updated by user {UserId}", id, userId);

            return Ok(new { message = "Conversation updated" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating conversation {ConversationId}", id);
            return StatusCode(500, new { message = "An error occurred" });
        }
    }

    [HttpDelete("{id}")]
    public async Task<ActionResult> DeleteConversation(string id)
    {
        try
        {
            var userId = User.FindFirst("userId")?.Value;

            if (string.IsNullOrEmpty(userId))
            {
                return Unauthorized(new { message = "User not authenticated" });
            }

            var conversation = await _conversationRepository.GetByIdWithParticipantsAsync(id);

            if (conversation == null)
            {
                return NotFound(new { message = "Conversation not found" });
            }

            // Check if user is a participant (and admin for groups)
            var participant = conversation.Participants.FirstOrDefault(p => p.UserId == userId);
            if (participant == null)
            {
                return Forbid();
            }

            if (conversation.Type == ConversationType.Group && !participant.IsAdmin)
            {
                return Forbid();
            }

            await _conversationRepository.DeleteAsync(id);

            _logger.LogInformation("Conversation {ConversationId} deleted by user {UserId}", id, userId);

            return Ok(new { message = "Conversation deleted" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting conversation {ConversationId}", id);
            return StatusCode(500, new { message = "An error occurred" });
        }
    }

    [HttpPost("{id}/participants")]
    public async Task<ActionResult> AddParticipant(string id, [FromBody] AddParticipantRequest request)
    {
        try
        {
            var userId = User.FindFirst("userId")?.Value;

            if (string.IsNullOrEmpty(userId))
            {
                return Unauthorized(new { message = "User not authenticated" });
            }

            var conversation = await _conversationRepository.GetByIdWithParticipantsAsync(id);

            if (conversation == null)
            {
                return NotFound(new { message = "Conversation not found" });
            }

            if (conversation.Type != ConversationType.Group)
            {
                return BadRequest(new { message = "Cannot add participants to direct conversations" });
            }

            // Check if user is admin
            var participant = conversation.Participants.FirstOrDefault(p => p.UserId == userId);
            if (participant == null || !participant.IsAdmin)
            {
                return Forbid();
            }

            // Check if new participant exists
            var newParticipant = await _userRepository.GetByIdAsync(request.UserId);
            if (newParticipant == null)
            {
                return BadRequest(new { message = "User not found" });
            }

            // Check if already a participant
            if (await _conversationRepository.IsParticipantAsync(id, request.UserId))
            {
                return BadRequest(new { message = "User is already a participant" });
            }

            await _conversationRepository.AddParticipantAsync(id, request.UserId);

            _logger.LogInformation("User {NewUserId} added to conversation {ConversationId} by {UserId}",
                request.UserId, id, userId);

            return Ok(new { message = "Participant added" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error adding participant to conversation {ConversationId}", id);
            return StatusCode(500, new { message = "An error occurred" });
        }
    }

    [HttpDelete("{id}/participants/{participantId}")]
    public async Task<ActionResult> RemoveParticipant(string id, string participantId)
    {
        try
        {
            var userId = User.FindFirst("userId")?.Value;

            if (string.IsNullOrEmpty(userId))
            {
                return Unauthorized(new { message = "User not authenticated" });
            }

            var conversation = await _conversationRepository.GetByIdWithParticipantsAsync(id);

            if (conversation == null)
            {
                return NotFound(new { message = "Conversation not found" });
            }

            if (conversation.Type != ConversationType.Group)
            {
                return BadRequest(new { message = "Cannot remove participants from direct conversations" });
            }

            // Check if user is admin or removing themselves
            var currentParticipant = conversation.Participants.FirstOrDefault(p => p.UserId == userId);
            if (currentParticipant == null)
            {
                return Forbid();
            }

            if (participantId != userId && !currentParticipant.IsAdmin)
            {
                return Forbid();
            }

            // Check if participant exists in conversation
            if (!await _conversationRepository.IsParticipantAsync(id, participantId))
            {
                return BadRequest(new { message = "User is not a participant" });
            }

            await _conversationRepository.RemoveParticipantAsync(id, participantId);

            _logger.LogInformation("User {RemovedUserId} removed from conversation {ConversationId} by {UserId}",
                participantId, id, userId);

            return Ok(new { message = "Participant removed" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error removing participant from conversation {ConversationId}", id);
            return StatusCode(500, new { message = "An error occurred" });
        }
    }
}

// Response DTO wrapper
public record ConversationsResponseDto(List<ConversationDto> Data);
