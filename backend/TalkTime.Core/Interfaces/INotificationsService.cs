namespace TalkTime.Core.Interfaces;

public interface INotificationsService
{
    Task SendNotificationAsync(string userId, string title, string message, string? imageUrl, string? data);
}
