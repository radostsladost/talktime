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
    private readonly IRefreshTokenRepository _refreshTokenRepository;
    private readonly IUserFirebaseTokenRepository _firebaseTokenRepository;
    private readonly IJwtService _jwtService;
    private readonly ILogger<AuthController> _logger;
    private readonly IConfiguration _configuration;

    public AuthController(
        IUserRepository userRepository,
        IRefreshTokenRepository refreshTokenRepository,
        IUserFirebaseTokenRepository firebaseTokenRepository,
        IJwtService jwtService,
        ILogger<AuthController> logger,
        IConfiguration configuration)
    {
        _userRepository = userRepository;
        _refreshTokenRepository = refreshTokenRepository;
        _firebaseTokenRepository = firebaseTokenRepository;
        _jwtService = jwtService;
        _logger = logger;
        _configuration = configuration;
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

            var (accessToken, refreshToken, accessTokenExpires, refreshTokenExpires) = await GenerateTokensAsync(user);

            // Update online status
            await _userRepository.SetOnlineStatusAsync(user.Id, true);

            // Save Firebase token if provided
            if (!string.IsNullOrWhiteSpace(request.FirebaseToken))
            {
                await SaveFirebaseTokenAsync(user.Id, request.FirebaseToken, request.DeviceId, request.DeviceInfo);
            }

            _logger.LogInformation("User {UserId} logged in successfully", user.Id);

            return Ok(new LoginResponse(
                accessToken,
                refreshToken,
                accessTokenExpires,
                refreshTokenExpires,
                new UserProfileDto(user.Id, user.Username, user.AvatarUrl, user.Email, user.Description)
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

            var (accessToken, refreshToken, accessTokenExpires, refreshTokenExpires) = await GenerateTokensAsync(user);

            // Save Firebase token if provided
            if (!string.IsNullOrWhiteSpace(request.FirebaseToken))
            {
                await SaveFirebaseTokenAsync(user.Id, request.FirebaseToken, request.DeviceId, request.DeviceInfo);
            }

            _logger.LogInformation("New user registered: {UserId} ({Username})", user.Id, user.Username);

            return Ok(new LoginResponse(
                accessToken,
                refreshToken,
                accessTokenExpires,
                refreshTokenExpires,
                new UserProfileDto(user.Id, user.Username, user.AvatarUrl, user.Email, user.Description)
            ));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during registration for email {Email}", request.Email);
            return StatusCode(500, new { message = "An error occurred during registration" });
        }
    }

    [HttpPost("refresh")]
    [AllowAnonymous]
    public async Task<ActionResult<RefreshTokenResponse>> RefreshToken([FromBody] RefreshTokenRequest request)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(request.RefreshToken))
            {
                return BadRequest(new { message = "Refresh token is required" });
            }

            // Hash the provided token to look it up
            var tokenHash = _jwtService.HashToken(request.RefreshToken);
            var storedToken = await _refreshTokenRepository.GetByTokenHashAsync(tokenHash);

            if (storedToken == null)
            {
                _logger.LogWarning("Refresh token not found");
                return Unauthorized(new { message = "Invalid refresh token" });
            }

            if (!storedToken.IsActive)
            {
                _logger.LogWarning("Refresh token is no longer active for user {UserId}", storedToken.UserId);

                // If someone tries to use a revoked token, revoke all tokens for this user (potential token theft)
                if (storedToken.IsRevoked)
                {
                    // await _refreshTokenRepository.RevokeAllByUserIdAsync(storedToken.UserId);
                    _logger.LogWarning("Potential token theft detected for user {UserId}. All tokens revoked.", storedToken.UserId);
                }

                return Unauthorized(new { message = "Invalid refresh token" });
            }

            var user = storedToken.User;
            if (user == null)
            {
                _logger.LogWarning("User not found for refresh token");
                return Unauthorized(new { message = "Invalid refresh token" });
            }

            // Generate new tokens (token rotation)
            var (newAccessToken, newRefreshToken, accessTokenExpires, refreshTokenExpires) = await GenerateTokensAsync(user, storedToken.Id);

            // Revoke the old refresh token
            await _refreshTokenRepository.RevokeAsync(tokenHash, storedToken.Id);

            _logger.LogInformation("Tokens refreshed for user {UserId}", user.Id);

            return Ok(new RefreshTokenResponse(
                newAccessToken,
                newRefreshToken,
                accessTokenExpires,
                refreshTokenExpires
            ));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during token refresh");
            return StatusCode(500, new { message = "An error occurred during token refresh" });
        }
    }

    [HttpPost("revoke")]
    [Authorize]
    public async Task<ActionResult> RevokeToken([FromBody] RevokeTokenRequest request)
    {
        try
        {
            var userId = User.FindFirst("userId")?.Value;

            if (string.IsNullOrEmpty(userId))
            {
                return BadRequest(new { message = "User not found in token" });
            }

            if (string.IsNullOrWhiteSpace(request.RefreshToken))
            {
                return BadRequest(new { message = "Refresh token is required" });
            }

            var tokenHash = _jwtService.HashToken(request.RefreshToken);
            var storedToken = await _refreshTokenRepository.GetByTokenHashAsync(tokenHash);

            if (storedToken == null || storedToken.UserId != userId)
            {
                return BadRequest(new { message = "Invalid refresh token" });
            }

            await _refreshTokenRepository.RevokeAsync(tokenHash);

            _logger.LogInformation("Refresh token revoked for user {UserId}", userId);

            return Ok(new { message = "Token revoked successfully" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during token revocation");
            return StatusCode(500, new { message = "An error occurred during token revocation" });
        }
    }

    [HttpPost("logout")]
    [Authorize]
    public async Task<ActionResult> Logout([FromBody] RevokeTokenRequest? request = null)
    {
        try
        {
            var userId = User.FindFirst("userId")?.Value;

            if (string.IsNullOrEmpty(userId))
            {
                return BadRequest(new { message = "User not found in token" });
            }

            // Revoke the specific refresh token if provided
            if (!string.IsNullOrWhiteSpace(request?.RefreshToken))
            {
                var tokenHash = _jwtService.HashToken(request.RefreshToken);
                await _refreshTokenRepository.RevokeAsync(tokenHash);
            }
            else
            {
                // Revoke all refresh tokens for this user
                // await _refreshTokenRepository.RevokeAllByUserIdAsync(userId);
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

    [HttpPost("logout-all")]
    [Authorize]
    public async Task<ActionResult> LogoutAll()
    {
        try
        {
            var userId = User.FindFirst("userId")?.Value;

            if (string.IsNullOrEmpty(userId))
            {
                return BadRequest(new { message = "User not found in token" });
            }

            // Revoke all refresh tokens for this user
            await _refreshTokenRepository.RevokeAllByUserIdAsync(userId);
            await _userRepository.SetOnlineStatusAsync(userId, false);

            _logger.LogInformation("User {UserId} logged out from all devices", userId);

            return Ok(new { message = "Logged out from all devices successfully" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during logout-all");
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

            return Ok(new UserProfileDto(user.Id, user.Username, user.AvatarUrl, user.Email, user.Description));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting current user");
            return StatusCode(500, new { message = "An error occurred" });
        }
    }

    [HttpPut("me")]
    [Authorize]
    public async Task<IActionResult> UpdateProfile([FromBody] UpdateProfileRequest dto)
    {
        if (!ModelState.IsValid)
        {
            return BadRequest(ModelState);
        }

        var userId = User.FindFirst("userId")?.Value;
        var user = await _userRepository.GetByIdAsync(userId!);
        if (user == null || dto == null)
        {
            return NotFound(new { message = "User not found" });
        }

        if (dto.Username != null && dto.Username.Trim().Length >= 1) user.Username = dto.Username.Trim();
        // if (dto.AvatarUrl != null) user.AvatarUrl = dto.AvatarUrl;
        if (dto.Email != null && dto.Email.Trim().Length >= 1 && dto.Email.Contains('@')) user.Email = dto.Email.Trim();
        if (dto.Description != null) user.Description = dto.Description;


        if (dto.NewPassword != null && dto.NewPassword.Length >= 1)
        {
            if (!BCrypt.Net.BCrypt.Verify(dto.Password ?? "", user.PasswordHash))
            {
                _logger.LogWarning("Update profile failed: Invalid password for user {UserId}", user.Id);
                return Unauthorized(new { message = "Invalid old password" });
            }

            user.PasswordHash = BCrypt.Net.BCrypt.HashPassword(dto.NewPassword);
        }

        await _userRepository.UpdateAsync(user);

        return Ok(new UserProfileDto(user.Id, user.Username, user.AvatarUrl, user.Email, user.Description));
    }

    /// <summary>
    /// Generate access token and refresh token for a user
    /// </summary>
    private async Task<(string AccessToken, string RefreshToken, DateTime AccessTokenExpires, DateTime RefreshTokenExpires)> GenerateTokensAsync(User user, string? replacedTokenId = null)
    {
        // Generate access token
        var accessToken = _jwtService.GenerateToken(user);
        var accessTokenExpires = DateTime.UtcNow.AddMinutes(
            int.Parse(_configuration["Jwt:ExpirationInMinutes"] ?? "60")
        );

        // Generate refresh token
        var refreshToken = _jwtService.GenerateRefreshToken();
        var refreshTokenExpires = DateTime.UtcNow.AddDays(_jwtService.GetRefreshTokenExpirationDays());

        // Get client info
        var ipAddress = HttpContext.Connection.RemoteIpAddress?.ToString();
        var deviceInfo = HttpContext.Request.Headers.UserAgent.ToString();

        // Store refresh token in database
        var refreshTokenEntity = new RefreshToken
        {
            Id = Guid.NewGuid().ToString(),
            TokenHash = _jwtService.HashToken(refreshToken),
            UserId = user.Id,
            ExpiresAt = refreshTokenExpires,
            CreatedAt = DateTime.UtcNow,
            IpAddress = ipAddress,
            DeviceInfo = deviceInfo?.Length > 500 ? deviceInfo[..500] : deviceInfo
        };

        await _refreshTokenRepository.CreateAsync(refreshTokenEntity);

        return (accessToken, refreshToken, accessTokenExpires, refreshTokenExpires);
    }

    /// <summary>
    /// Register or update Firebase token for push notifications
    /// </summary>
    [HttpPost("firebase-token")]
    [Authorize]
    public async Task<ActionResult> RegisterFirebaseToken([FromBody] RegisterFirebaseTokenRequest request)
    {
        try
        {
            var userId = User.FindFirst("userId")?.Value;

            if (string.IsNullOrEmpty(userId))
            {
                return BadRequest(new { message = "User not found in token" });
            }

            if (string.IsNullOrWhiteSpace(request.Token))
            {
                return BadRequest(new { message = "Firebase token is required" });
            }

            await SaveFirebaseTokenAsync(userId, request.Token, request.DeviceId, request.DeviceInfo, request.MessagePreview ?? true);

            _logger.LogInformation("Firebase token registered for user {UserId}", userId);

            return Ok(new { message = "Firebase token registered successfully" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error registering Firebase token");
            return StatusCode(500, new { message = "An error occurred during token registration" });
        }
    }

    /// <summary>
    /// Remove Firebase token for this device (disables push notifications for the current device).
    /// </summary>
    [HttpDelete("firebase-token")]
    [Authorize]
    public async Task<ActionResult> DeleteFirebaseToken([FromBody] DeleteFirebaseTokenRequest request)
    {
        try
        {
            var userId = User.FindFirst("userId")?.Value;

            if (string.IsNullOrEmpty(userId))
            {
                return BadRequest(new { message = "User not found in token" });
            }

            if (string.IsNullOrWhiteSpace(request.Token))
            {
                return BadRequest(new { message = "Firebase token is required" });
            }

            var deleted = await _firebaseTokenRepository.DeleteByUserIdAndTokenAsync(userId, request.Token);
            if (!deleted)
            {
                return NotFound(new { message = "Token not found or already removed" });
            }

            _logger.LogInformation("Firebase token removed for user {UserId}", userId);
            return Ok(new { message = "Notifications disabled for this device" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error removing Firebase token");
            return StatusCode(500, new { message = "An error occurred" });
        }
    }

    /// <summary>
    /// Save Firebase token for a user
    /// </summary>
    private async Task SaveFirebaseTokenAsync(string userId, string token, string? deviceId, string? deviceInfo, bool messagePreview = true)
    {
        try
        {
            // Get device info from request headers if not provided
            if (string.IsNullOrEmpty(deviceInfo))
            {
                deviceInfo = HttpContext.Request.Headers.UserAgent.ToString();
                if (deviceInfo?.Length > 500)
                {
                    deviceInfo = deviceInfo[..500];
                }
            }

            var firebaseToken = new UserFirebaseToken
            {
                UserId = userId,
                Token = token,
                DeviceId = deviceId,
                DeviceInfo = deviceInfo,
                MessagePreview = messagePreview,
                CreatedAt = DateTime.UtcNow,
                LastUsedAt = DateTime.UtcNow
            };

            await _firebaseTokenRepository.UpsertAsync(firebaseToken);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error saving Firebase token for user {UserId}", userId);
            // Don't throw - this is not critical for login/registration
        }
    }
}
