using TalkTime.Core.Entities;

namespace TalkTime.Core.Interfaces;

public interface IUserRepository
{
    Task<User?> GetByIdAsync(string id);
    Task<User?> GetByEmailAsync(string email);
    Task<User?> GetByUsernameAsync(string username);
    Task<List<User>> GetAllAsync();
    Task<List<User>> GetByIdsAsync(IEnumerable<string> ids);
    Task<List<User>> SearchAsync(string query, int limit = 20);
    Task<User> CreateAsync(User user);
    Task<User> UpdateAsync(User user);
    Task DeleteAsync(string id);
    Task SetOnlineStatusAsync(string userId, bool isOnline);
    Task<bool> ExistsAsync(string id);
    Task<bool> EmailExistsAsync(string email);
    Task<bool> UsernameExistsAsync(string username);
}
