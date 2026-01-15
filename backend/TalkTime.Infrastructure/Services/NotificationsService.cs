using TalkTime.Core.Interfaces;
using FirebaseAdmin.Messaging;
using Microsoft.Extensions.Logging;
using FirebaseAdmin;

namespace TalkTime.Infrastructure.Services;

public class NotificationsService(
    IUserFirebaseTokenRepository firebaseTokenRepository,
    ILogger<NotificationsService> logger) : INotificationsService
{

    public async Task SendNotificationAsync(string userId, string title, string message, string? imageUrl, string? data)
    {
        try
        {
            // Check if Firebase is initialized
            if (FirebaseMessaging.DefaultInstance == null)
            {
                logger.LogWarning("Firebase Admin SDK is not initialized. Cannot send notifications to user {UserId}", userId);
                return;
            }

            // Get all Firebase tokens for the user
            var tokens = await firebaseTokenRepository.GetByUserIdAsync(userId);

            if (!tokens.Any())
            {
                logger.LogDebug("No Firebase tokens found for user {UserId}", userId);
                return;
            }

            // Prepare the notification message
            var notification = new Notification
            {
                Title = title,
                Body = message,
                ImageUrl = imageUrl
            };

            // Prepare data payload
            var dataDict = new Dictionary<string, string>();
            if (!string.IsNullOrEmpty(data))
            {
                dataDict["data"] = data;
            }
            dataDict["userId"] = userId;

            // Send to all user's devices
            var tasks = tokens.Select(async token =>
            {
                try
                {
                    // Validate token is not null or empty
                    if (string.IsNullOrWhiteSpace(token.Token))
                    {
                        logger.LogWarning("Firebase token is null or empty for token {TokenId} of user {UserId}", token.Id, userId);
                        return;
                    }

                    var firebaseMessage = new Message
                    {
                        Token = token.Token,
                        Notification = notification,
                        Data = dataDict,
                        Android = new AndroidConfig
                        {
                            Priority = Priority.High,
                            Notification = new AndroidNotification
                            {
                                Title = title,
                                Body = message,
                                ImageUrl = imageUrl,
                                Sound = "default",
                                ChannelId = "default"
                            }
                        },
                        Apns = new ApnsConfig
                        {
                            Aps = new Aps
                            {
                                Alert = new ApsAlert
                                {
                                    Title = title,
                                    Body = message
                                },
                                Sound = "default",
                                Badge = 1
                            }
                        }
                    };

                    // Double-check Firebase is initialized before sending
                    if (FirebaseMessaging.DefaultInstance == null)
                    {
                        logger.LogError("Firebase Admin SDK became uninitialized while processing notification for user {UserId}", userId);
                        return;
                    }

                    var response = await FirebaseMessaging.DefaultInstance.SendAsync(firebaseMessage);
                    logger.LogInformation("Firebase notification sent successfully to token {TokenId} for user {UserId}. MessageId: {MessageId}",
                        token.Id, userId, response);

                    // Update last used timestamp
                    await firebaseTokenRepository.UpdateLastUsedAsync(token.Token);
                }
                catch (FirebaseMessagingException ex)
                {
                    logger.LogWarning(ex, "Failed to send Firebase notification to token {TokenId} for user {UserId}. Error: {ErrorCode}",
                        token.Id, userId, ex.ErrorCode);

                    // If token is invalid, remove it
                    if (ex.ErrorCode == ErrorCode.InvalidArgument || ex.ErrorCode == ErrorCode.NotFound ||
                        ex.ErrorCode == ErrorCode.Unauthenticated)
                    {
                        logger.LogInformation("Removing invalid Firebase token {TokenId} for user {UserId}", token.Id, userId);
                        await firebaseTokenRepository.DeleteAsync(token.Id);
                    }
                }
                catch (Exception ex)
                {
                    logger.LogError(ex, "Unexpected error sending Firebase notification to token {TokenId} for user {UserId}",
                        token.Id, userId);
                }
            });

            await Task.WhenAll(tasks);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error sending Firebase notification to user {UserId}", userId);
        }
    }
}
