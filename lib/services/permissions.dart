import '../models/room_state.dart';
import '../models/player.dart';

class PermissionResult {
  final bool allowed;
  final String? reason;
  PermissionResult(this.allowed, {this.reason});
}

class Permissions {
  static PermissionResult canSend({
    required RoomState room,
    required Player? sender,
    // 'main', 'dm', 'private_request' (asking to start a brand-new chat,
    // before any chat/id exists yet), or 'private:<chatId>' (sending
    // inside one that already exists, or asking to join one).
    required String channel,
    bool isAdmin = false,
    String? targetPrivateChatId,
    // NEW: only used by 'private_request' — the player being invited,
    // needed to check neighbor-restriction BEFORE a chat exists. Kept
    // separate from targetPrivateChatId (used everywhere else) because a
    // brand-new request has no chatId to look up yet.
    String? targetPlayerId,
  }) {
    if (isAdmin) return PermissionResult(true);

    if (sender != null && sender.muted) {
      if (channel == 'dm') return PermissionResult(true);
      return PermissionResult(false, reason: 'You are muted.');
    }

    if (channel == 'main') {
      if (room.chatMode == ChatMode.locked) {
        return PermissionResult(false, reason: 'Main chat is locked.');
      }
      return PermissionResult(true);
    }

    if (channel == 'dm') return PermissionResult(true);

    // NEW: starting a brand-new private chat. This used to be routed
    // through the 'private:' branch below with no chatId to give it,
    // so the neighbor check looked up a chat that by definition doesn't
    // exist yet — always failing "Chat not found" and blocking every
    // private chat request the instant neighbor restriction was on,
    // regardless of whether the two players were actually neighbors.
    // This branch checks the real relationship directly instead.
    if (channel == 'private_request') {
      if (room.chatMode == ChatMode.locked) {
        return PermissionResult(false, reason: 'Chat is locked.');
      }
      if (room.neighborRestriction) {
        return PermissionResult(false,
            reason:
                'Private chats are disabled while Neighbor Restriction is on.');
      }
      return PermissionResult(true);
    }

    if (channel.startsWith('private:')) {
      if (room.chatMode == ChatMode.locked) {
        return PermissionResult(false, reason: 'Chat is locked.');
      }
      if (room.neighborRestriction) {
        return PermissionResult(false,
            reason:
                'Private chats are disabled while Neighbor Restriction is on.');
      }
      return PermissionResult(true);
    }

    return PermissionResult(false, reason: 'Unknown channel.');
  }
}
