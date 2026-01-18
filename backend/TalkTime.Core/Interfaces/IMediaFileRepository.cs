using TalkTime.Core.Entities;

namespace TalkTime.Core.Interfaces;

public interface IMediaFileRepository
{
    Task<MediaFile?> GetByIdAsync(string id);
    Task<MediaFile> CreateAsync(MediaFile mediaFile);
    Task DeleteAsync(string id);
}
