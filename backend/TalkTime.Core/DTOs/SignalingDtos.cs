namespace TalkTime.Core.DTOs;

/// <summary>
/// Base class for all signaling messages.
/// FromDeviceId/ToDeviceId identify the source and target devices for WebRTC signaling.
/// </summary>
public record SignalingMessage(
    string Type,
    string FromDeviceId,
    string ToDeviceId,
    string? RoomId
);

/// <summary>
/// Offer for initiating a WebRTC connection
/// </summary>
public record SignalingOffer(
    string FromDeviceId,
    string ToDeviceId,
    string? RoomId,
    string Sdp
) : SignalingMessage("offer", FromDeviceId, ToDeviceId, RoomId);

/// <summary>
/// Answer to a WebRTC offer
/// </summary>
public record SignalingAnswer(
    string FromDeviceId,
    string ToDeviceId,
    string? RoomId,
    string Sdp
) : SignalingMessage("answer", FromDeviceId, ToDeviceId, RoomId);

/// <summary>
/// ICE candidate for WebRTC connection establishment
/// </summary>
public record SignalingIceCandidate(
    string FromDeviceId,
    string ToDeviceId,
    string? RoomId,
    string Candidate,
    string? SdpMid,
    int? SdpMLineIndex
) : SignalingMessage("ice-candidate", FromDeviceId, ToDeviceId, RoomId);

/// <summary>
/// Call initiation request
/// </summary>
public record CallRequest(
    string CallerId,
    string CalleeId,
    string CallType, // "audio", "video", "screen"
    string? RoomId
);

/// <summary>
/// Call response (accept/reject)
/// </summary>
public record CallResponse(
    string CallId,
    string ResponderId,
    bool Accepted,
    string? Reason
);

/// <summary>
/// Call ended notification
/// </summary>
public record CallEnded(
    string CallId,
    string DeviceId,
    string Reason // "ended", "rejected", "timeout", "error"
);

/// <summary>
/// Incoming call notification
/// </summary>
public record IncomingCall(
    string CallId,
    UserDto Caller,
    string CallType,
    string? RoomId
);

/// <summary>
/// Group call / conference room
/// </summary>
public record RoomInfo(
    string RoomId,
    string Name,
    List<UserDto> Participants,
    string CreatedBy,
    DateTime CreatedAt,
    string? InviteKey = null
);

/// <summary>
/// Join room request
/// </summary>
public record JoinRoomRequest(
    string RoomId,
    string UserId
);

/// <summary>
/// Leave room request
/// </summary>
public record LeaveRoomRequest(
    string RoomId,
    string UserId,
    string Reason
);

/// <summary>
/// User joined/left room notification
/// </summary>
public record RoomParticipantUpdate(
    string RoomId,
    UserDto User,
    string Action // "joined", "left"
);
