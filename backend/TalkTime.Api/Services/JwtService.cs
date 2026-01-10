using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.IdentityModel.Tokens;
using TalkTime.Core.Entities;

namespace TalkTime.Api.Services;

public interface IJwtService
{
    string GenerateToken(User user);
    ClaimsPrincipal? ValidateToken(string token);
    string? GetUserIdFromToken(string token);

    // Refresh token methods
    string GenerateRefreshToken();
    string HashToken(string token);
    bool VerifyTokenHash(string token, string hash);
    int GetRefreshTokenExpirationDays();
}

public class JwtService : IJwtService
{
    private readonly IConfiguration _configuration;
    private readonly string _secret;
    private readonly string _issuer;
    private readonly string _audience;
    private readonly int _expirationInMinutes;
    private readonly int _refreshTokenExpirationDays;

    public JwtService(IConfiguration configuration)
    {
        _configuration = configuration;
        _secret = _configuration["Jwt:Secret"] ?? throw new InvalidOperationException("JWT Secret not configured");
        _issuer = _configuration["Jwt:Issuer"] ?? "TalkTime";
        _audience = _configuration["Jwt:Audience"] ?? "TalkTimeUsers";
        _expirationInMinutes = int.Parse(_configuration["Jwt:ExpirationInMinutes"] ?? "60"); // Default 1 hour for access token
        _refreshTokenExpirationDays = int.Parse(_configuration["Jwt:RefreshTokenExpirationDays"] ?? "30"); // Default 30 days
    }

    public string GenerateToken(User user)
    {
        var securityKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_secret));
        var credentials = new SigningCredentials(securityKey, SecurityAlgorithms.HmacSha256);

        var claims = new[]
        {
            new Claim(JwtRegisteredClaimNames.Sub, user.Id),
            new Claim(JwtRegisteredClaimNames.Email, user.Email),
            new Claim(JwtRegisteredClaimNames.UniqueName, user.Username),
            new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
            new Claim("userId", user.Id),
            new Claim("username", user.Username)
        };

        var token = new JwtSecurityToken(
            issuer: _issuer,
            audience: _audience,
            claims: claims,
            expires: DateTime.UtcNow.AddMinutes(_expirationInMinutes),
            signingCredentials: credentials
        );

        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    public ClaimsPrincipal? ValidateToken(string token)
    {
        var tokenHandler = new JwtSecurityTokenHandler();
        var key = Encoding.UTF8.GetBytes(_secret);

        try
        {
            var principal = tokenHandler.ValidateToken(token, new TokenValidationParameters
            {
                ValidateIssuerSigningKey = true,
                IssuerSigningKey = new SymmetricSecurityKey(key),
                ValidateIssuer = true,
                ValidIssuer = _issuer,
                ValidateAudience = true,
                ValidAudience = _audience,
                ValidateLifetime = true,
                ClockSkew = TimeSpan.Zero
            }, out SecurityToken validatedToken);

            return principal;
        }
        catch
        {
            return null;
        }
    }

    public string? GetUserIdFromToken(string token)
    {
        var principal = ValidateToken(token);
        return principal?.FindFirst("userId")?.Value
            ?? principal?.FindFirst(JwtRegisteredClaimNames.Sub)?.Value;
    }

    /// <summary>
    /// Generate a cryptographically secure refresh token
    /// </summary>
    public string GenerateRefreshToken()
    {
        var randomBytes = new byte[64];
        using var rng = RandomNumberGenerator.Create();
        rng.GetBytes(randomBytes);
        return Convert.ToBase64String(randomBytes);
    }

    /// <summary>
    /// Hash a token using SHA256 for secure storage
    /// </summary>
    public string HashToken(string token)
    {
        using var sha256 = SHA256.Create();
        var bytes = Encoding.UTF8.GetBytes(token);
        var hash = sha256.ComputeHash(bytes);
        return Convert.ToBase64String(hash);
    }

    /// <summary>
    /// Verify a token against its hash
    /// </summary>
    public bool VerifyTokenHash(string token, string hash)
    {
        var tokenHash = HashToken(token);
        return tokenHash == hash;
    }

    /// <summary>
    /// Get the refresh token expiration in days
    /// </summary>
    public int GetRefreshTokenExpirationDays()
    {
        return _refreshTokenExpirationDays;
    }
}
