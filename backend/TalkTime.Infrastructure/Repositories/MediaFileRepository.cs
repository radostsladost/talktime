using Microsoft.EntityFrameworkCore;
using TalkTime.Core.Entities;
using TalkTime.Core.Interfaces;
using TalkTime.Infrastructure.Data;

namespace TalkTime.Infrastructure.Repositories;

public class MediaFileRepository : IMediaFileRepository
{
    private readonly AppDbContext _context;

    public MediaFileRepository(AppDbContext context)
    {
        _context = context;
    }

    public async Task<MediaFile?> GetByIdAsync(string id)
    {
        return await _context.MediaFiles
            .Include(m => m.Uploader)
            .FirstOrDefaultAsync(m => m.Id == id);
    }

    public async Task<MediaFile> CreateAsync(MediaFile mediaFile)
    {
        _context.MediaFiles.Add(mediaFile);
        await _context.SaveChangesAsync();
        return mediaFile;
    }

    public async Task DeleteAsync(string id)
    {
        var mediaFile = await _context.MediaFiles.FindAsync(id);
        if (mediaFile != null)
        {
            _context.MediaFiles.Remove(mediaFile);
            await _context.SaveChangesAsync();
        }
    }
}
