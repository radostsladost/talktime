using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TalkTime.Core.Entities;
using TalkTime.Core.Interfaces;

namespace TalkTime.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class MediaController : ControllerBase
{
    private readonly IMediaFileRepository _mediaFileRepository;
    private readonly IWebHostEnvironment _environment;
    private readonly ILogger<MediaController> _logger;
    private readonly IConfiguration _configuration;

    private static readonly string[] AllowedImageTypes = { "image/jpeg", "image/png", "image/gif", "image/webp" };
    private const long MaxFileSize = 10 * 1024 * 1024; // 10MB

    public MediaController(
        IMediaFileRepository mediaFileRepository,
        IWebHostEnvironment environment,
        ILogger<MediaController> logger,
        IConfiguration configuration)
    {
        _mediaFileRepository = mediaFileRepository;
        _environment = environment;
        _logger = logger;
        _configuration = configuration;
    }

    /// <summary>
    /// Upload an image file
    /// </summary>
    [HttpPost("upload")]
    [RequestSizeLimit(10 * 1024 * 1024)] // 10MB limit
    public async Task<ActionResult> UploadImage(IFormFile file)
    {
        try
        {
            var userId = User.FindFirst("userId")?.Value;
            if (string.IsNullOrEmpty(userId))
            {
                return Unauthorized(new { message = "User not authenticated" });
            }

            if (file == null || file.Length == 0)
            {
                return BadRequest(new { message = "No file provided" });
            }

            if (file.Length > MaxFileSize)
            {
                return BadRequest(new { message = "File size exceeds 10MB limit" });
            }

            if (!AllowedImageTypes.Contains(file.ContentType.ToLower()))
            {
                return BadRequest(new { message = "Invalid file type. Allowed types: JPEG, PNG, GIF, WebP" });
            }

            // Generate unique filename
            var fileId = Guid.NewGuid().ToString();
            var extension = Path.GetExtension(file.FileName);
            var fileName = $"{fileId}{extension}";

            // Save under wwwroot so UseStaticFiles serves them at /uploads/images/...
            var webRoot = _environment.WebRootPath ?? Path.Combine(_environment.ContentRootPath, "wwwroot");
            var uploadsPath = Path.Combine(webRoot, "uploads", "images");
            if (!Directory.Exists(uploadsPath))
            {
                Directory.CreateDirectory(uploadsPath);
            }

            var filePath = Path.Combine(uploadsPath, fileName);

            // Save file
            using (var stream = new FileStream(filePath, FileMode.Create))
            {
                await file.CopyToAsync(stream);
            }

            // URL path for static files: /uploads/images/{fileName} (no api prefix)
            var baseUrl = _configuration.GetSection("PublicUrl").Value?.TrimEnd('/') ?? $"{HttpContext.Request.Scheme}://{HttpContext.Request.Host}";
            var fileUrl = $"{baseUrl}/uploads/images/{fileName}";

            // Save to database (StoragePath is relative to wwwroot for consistency)
            var mediaFile = new MediaFile
            {
                Id = fileId,
                UploaderId = userId,
                FileName = file.FileName,
                ContentType = file.ContentType,
                Size = file.Length,
                StoragePath = Path.Combine("uploads", "images", fileName).Replace('\\', '/'),
                Url = fileUrl,
                CreatedAt = DateTime.UtcNow
            };

            await _mediaFileRepository.CreateAsync(mediaFile);

            _logger.LogInformation("Image uploaded: {FileId} by user {UserId}", fileId, userId);

            return Ok(new
            {
                data = new
                {
                    id = mediaFile.Id,
                    url = mediaFile.Url,
                    fileName = mediaFile.FileName,
                    contentType = mediaFile.ContentType,
                    size = mediaFile.Size
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error uploading image");
            return StatusCode(500, new { message = "An error occurred while uploading the image" });
        }
    }

    /// <summary>
    /// Get media file info
    /// </summary>
    [HttpGet("{id}")]
    public async Task<ActionResult> GetMediaFile(string id)
    {
        try
        {
            var userId = User.FindFirst("userId")?.Value;
            if (string.IsNullOrEmpty(userId))
            {
                return Unauthorized(new { message = "User not authenticated" });
            }

            var mediaFile = await _mediaFileRepository.GetByIdAsync(id);
            if (mediaFile == null)
            {
                return NotFound(new { message = "Media file not found" });
            }

            return Ok(new
            {
                data = new
                {
                    id = mediaFile.Id,
                    url = mediaFile.Url,
                    fileName = mediaFile.FileName,
                    contentType = mediaFile.ContentType,
                    size = mediaFile.Size
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting media file {Id}", id);
            return StatusCode(500, new { message = "An error occurred" });
        }
    }

    /// <summary>
    /// Delete a media file
    /// </summary>
    [HttpDelete("{id}")]
    public async Task<ActionResult> DeleteMediaFile(string id)
    {
        try
        {
            var userId = User.FindFirst("userId")?.Value;
            if (string.IsNullOrEmpty(userId))
            {
                return Unauthorized(new { message = "User not authenticated" });
            }

            var mediaFile = await _mediaFileRepository.GetByIdAsync(id);
            if (mediaFile == null)
            {
                return NotFound(new { message = "Media file not found" });
            }

            // Only uploader can delete
            if (mediaFile.UploaderId != userId)
            {
                return Forbid();
            }

            // Delete physical file (stored under wwwroot/uploads/...)
            var webRoot = _environment.WebRootPath ?? Path.Combine(_environment.ContentRootPath, "wwwroot");
            var filePath = Path.Combine(webRoot, mediaFile.StoragePath);
            if (System.IO.File.Exists(filePath))
            {
                System.IO.File.Delete(filePath);
            }

            // Delete database record
            await _mediaFileRepository.DeleteAsync(id);

            _logger.LogInformation("Media file deleted: {Id} by user {UserId}", id, userId);

            return Ok(new { message = "Media file deleted" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting media file {Id}", id);
            return StatusCode(500, new { message = "An error occurred" });
        }
    }
}
