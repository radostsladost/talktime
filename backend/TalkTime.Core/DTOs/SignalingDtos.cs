namespace TalkTime.Core.DTOs;

/// <summary>
/// Base class for all signaling messages
/// </summary>
public record SignalingMessage(
    string Type,
    string FromUserId,
    string ToUserId,
    string? RoomId
);

/// <summary>
/// Offer for initiating a WebRTC connection
/// </summary>
public record SignalingOffer(
    string FromUserId,
    string ToUserId,
    string? RoomId,
    string Sdp
) : SignalingMessage("offer", FromUserId, ToUserId, RoomId);

/// <summary>
/// Answer to a WebRTC offer
/// </summary>
public record SignalingAnswer(
    string FromUserId,
    string ToUserId,
    string? RoomId,
    string Sdp
) : SignalingMessage("answer", FromUserId, ToUserId, RoomId);

/// <summary>
/// ICE candidate for WebRTC connection establishment
/// </summary>
public record SignalingIceCandidate(
    string FromUserId,
    string ToUserId,
    string? RoomId,
    string Candidate,
    string? SdpMid,
    int? SdpMLineIndex
) : SignalingMessage("ice-candidate", FromUserId, ToUserId, RoomId);

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
    string UserId,
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
    DateTime CreatedAt
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
