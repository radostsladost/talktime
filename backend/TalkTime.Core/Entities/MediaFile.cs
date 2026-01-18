namespace TalkTime.Core.Entities;

/// <summary>
/// Represents an uploaded media file (image, etc.)
/// </summary>
public class MediaFile
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string UploaderId { get; set; } = string.Empty;
    
    /// <summary>
    /// Original filename
    /// </summary>
    public string FileName { get; set; } = string.Empty;
    
    /// <summary>
    /// MIME type (e.g., image/jpeg, image/gif)
    /// </summary>
    public string ContentType { get; set; } = string.Empty;
    
    /// <summary>
    /// File size in bytes
    /// </summary>
    public long Size { get; set; }
    
    /// <summary>
    /// Relative path where file is stored
    /// </summary>
    public string StoragePath { get; set; } = string.Empty;
    
    /// <summary>
    /// Public URL to access the file
    /// </summary>
    public string Url { get; set; } = string.Empty;
    
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    // Navigation properties
    public User Uploader { get; set; } = null!;
}
