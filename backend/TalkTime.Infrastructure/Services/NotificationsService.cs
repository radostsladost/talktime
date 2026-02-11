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
            if (FirebaseMessaging.DefaultInstance == null)
            {
                logger.LogWarning("Firebase Admin SDK is not initialized. Cannot send notifications to user {UserId}", userId);
                return;
            }

            var tokens = await firebaseTokenRepository.GetByUserIdAsync(userId);

            if (!tokens.Any())
            {
                logger.LogDebug("No Firebase tokens found for user {UserId}", userId);
                return;
            }

            var dataDict = new Dictionary<string, string>();
            if (!string.IsNullOrEmpty(data))
            {
                dataDict["data"] = data;
            }
            dataDict["userId"] = userId;

            var tasks = tokens.Select(async token =>
            {
                try
                {
                    if (string.IsNullOrWhiteSpace(token.Token))
                    {
                        logger.LogWarning("Firebase token is null or empty for token {TokenId} of user {UserId}", token.Id, userId);
                        return;
                    }

                    // Respect per-device message preview setting
                    var effectiveTitle = token.MessagePreview ? title : "New message";
                    var effectiveBody = token.MessagePreview ? message : "You have a new message";
                    var effectiveImageUrl = token.MessagePreview ? imageUrl : null;

                    var notification = new Notification
                    {
                        Title = effectiveTitle,
                        Body = effectiveBody,
                        ImageUrl = effectiveImageUrl
                    };

                    var firebaseMessage = new Message
                    {
                        Token = token.Token,
                        Notification = notification,
                        Data = dataDict,
                        Android = new AndroidConfig
                        {
                            Priority = Priority.Normal,
                            Notification = new AndroidNotification
                            {
                                Title = effectiveTitle,
                                Body = effectiveBody,
                                ImageUrl = effectiveImageUrl,
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
                                    Title = effectiveTitle,
                                    Body = effectiveBody
                                },
                                Sound = "default",
                                Badge = 1
                            }
                        }
                    };

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

    public async Task SendCallNotificationAsync(string userId, string? callerName, string? sessionId)
    {
        try
        {
            if (FirebaseMessaging.DefaultInstance == null)
            {
                logger.LogWarning("Firebase Admin SDK is not initialized. Cannot send notifications to user {UserId}", userId);
                return;
            }

            var tokens = await firebaseTokenRepository.GetByUserIdAsync(userId);
            if (tokens.Count == 0)
            {
                logger.LogDebug("No Firebase tokens found for user {UserId}", userId);
                return;
            }

            var dataDict = new Dictionary<string, string>() {
                { "type", "call"} ,
                { "call_type", "video"} ,
                { "caller_id", userId } ,
                { "caller_name", callerName ?? "Unknown"} ,
                { "session_id", sessionId ?? Guid.NewGuid().ToString()} ,
                { "call_id", sessionId ?? Guid.NewGuid().ToString()} ,
            };

            var tasks = tokens.Select(async token =>
            {
                try
                {
                    if (string.IsNullOrWhiteSpace(token.Token))
                    {
                        logger.LogWarning("Firebase token is null or empty for token {TokenId} of user {UserId}", token.Id, userId);
                        return;
                    }

                    var firebaseMessage = new Message
                    {
                        Token = token.Token,
                        Data = dataDict,
                        Android = new AndroidConfig
                        {
                            Priority = Priority.High,
                        },
                        Apns = new ApnsConfig
                        {
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
