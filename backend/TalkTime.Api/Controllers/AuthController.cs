using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TalkTime.Api.Services;
using TalkTime.Core.DTOs;
using TalkTime.Core.Entities;
using TalkTime.Core.Interfaces;

namespace TalkTime.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AuthController : ControllerBase
{
    private readonly IUserRepository _userRepository;
    private readonly IJwtService _jwtService;
    private readonly ILogger<AuthController> _logger;

    public AuthController(
        IUserRepository userRepository,
        IJwtService jwtService,
        ILogger<AuthController> logger)
    {
        _userRepository = userRepository;
        _jwtService = jwtService;
        _logger = logger;
    }

    [HttpPost("login")]
    [AllowAnonymous]
    public async Task<ActionResult<LoginResponse>> Login([FromBody] LoginRequest request)
    {
        try
        {
            var user = await _userRepository.GetByEmailAsync(request.Email);

            if (user == null)
            {
                _logger.LogWarning("Login attempt failed: User not found for email {Email}", request.Email);
                return Unauthorized(new { message = "Invalid email or password" });
            }

            if (!BCrypt.Net.BCrypt.Verify(request.Password, user.PasswordHash))
            {
                _logger.LogWarning("Login attempt failed: Invalid password for user {UserId}", user.Id);
                return Unauthorized(new { message = "Invalid email or password" });
            }

            var token = _jwtService.GenerateToken(user);

            // Update online status
            await _userRepository.SetOnlineStatusAsync(user.Id, true);

            _logger.LogInformation("User {UserId} logged in successfully", user.Id);

            return Ok(new LoginResponse(
                token,
                new UserDto(user.Id, user.Username, user.AvatarUrl)
            ));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during login for email {Email}", request.Email);
            return StatusCode(500, new { message = "An error occurred during login" });
        }
    }

    [HttpPost("register")]
    [AllowAnonymous]
    public async Task<ActionResult<LoginResponse>> Register([FromBody] RegisterRequest request)
    {
        try
        {
            // Check if email already exists
            if (await _userRepository.EmailExistsAsync(request.Email))
            {
                return BadRequest(new { message = "Email already registered" });
            }

            // Check if username already exists
            if (await _userRepository.UsernameExistsAsync(request.Username))
            {
                return BadRequest(new { message = "Username already taken" });
            }

            // Create new user
            var user = new User
            {
                Id = Guid.NewGuid().ToString(),
                Username = request.Username,
                Email = request.Email,
                PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.Password),
                IsOnline = true,
                CreatedAt = DateTime.UtcNow
            };

            await _userRepository.CreateAsync(user);

            var token = _jwtService.GenerateToken(user);

            _logger.LogInformation("New user registered: {UserId} ({Username})", user.Id, user.Username);

            return Ok(new LoginResponse(
                token,
                new UserDto(user.Id, user.Username, user.AvatarUrl)
            ));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during registration for email {Email}", request.Email);
            return StatusCode(500, new { message = "An error occurred during registration" });
        }
    }

    [HttpPost("logout")]
    [Authorize]
    public async Task<ActionResult> Logout()
    {
        try
        {
            var userId = User.FindFirst("userId")?.Value;

            if (string.IsNullOrEmpty(userId))
            {
                return BadRequest(new { message = "User not found in token" });
            }

            await _userRepository.SetOnlineStatusAsync(userId, false);

            _logger.LogInformation("User {UserId} logged out", userId);

            return Ok(new { message = "Logged out successfully" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during logout");
            return StatusCode(500, new { message = "An error occurred during logout" });
        }
    }

    [HttpGet("me")]
    [Authorize]
    public async Task<ActionResult<UserDto>> GetCurrentUser()
    {
        try
        {
            var userId = User.FindFirst("userId")?.Value;

            if (string.IsNullOrEmpty(userId))
            {
                return BadRequest(new { message = "User not found in token" });
            }

            var user = await _userRepository.GetByIdAsync(userId);

            if (user == null)
            {
                return NotFound(new { message = "User not found" });
            }

            return Ok(new UserDto(user.Id, user.Username, user.AvatarUrl));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting current user");
            return StatusCode(500, new { message = "An error occurred" });
        }
    }
}
