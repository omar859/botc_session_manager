class MessageType {
  static const joinRequest = 'join_request';
  static const joinApproved = 'join_approved';
  static const joinDeclined = 'join_declined';
  static const seatingUpdate = 'seating_update';
  static const chatMessage = 'chat_message';
  static const dmMessage = 'dm_message';

  static const privateChatRequest = 'private_chat_request';
  static const privateChatRequestAccept = 'private_chat_request_accept';
  static const privateChatRequestDecline = 'private_chat_request_decline';

  static const joinChatRequest = 'join_chat_request';
  static const joinChatAccept = 'join_chat_accept';
  static const joinChatDecline = 'join_chat_decline';

  static const privateMessage = 'private_message';
  static const leavePrivateChat = 'leave_private_chat';
  static const chatModeChange = 'chat_mode_change';
  static const neighborModeChange = 'neighbor_mode_change';
  static const mutePlayer = 'mute_player';
  static const unmutePlayer = 'unmute_player';
  static const forceCloseChat = 'force_close_chat';
  static const forceCloseAllChats = 'force_close_all_chats';
  static const disconnect = 'disconnect';
  static const reconnect = 'reconnect';
  static const scriptUpload = 'script_upload';
  static const requestScript = 'request_script';
  static const heartbeat = 'heartbeat';

  // NEW: script character list (public) and character assignment (private,
  // sent only to the one player it belongs to)
  static const scriptCharactersUpdate = 'script_characters_update';
  static const characterAssigned = 'character_assigned';

  // NEW: alignment (good/evil) is tracked separately from character —
  // the Storyteller can flip a player's alignment without reassigning
  // their character. Sent privately to the one player it belongs to,
  // same treatment as characterAssigned, for the same reason (it's
  // secret info, never broadcast wholesale).
  static const setPlayerAlignment = 'set_player_alignment';

  // NEW: admin-controlled countdown timer
  static const countdownStart = 'countdown_start';
  static const countdownCancel = 'countdown_cancel';

  // NEW: storyteller-controlled BOTC status — alive/dead and whether a
  // dead player has used their one ghost vote. Public info at the table,
  // so (like seating) this is broadcast to everyone, not admin-only.
  static const setPlayerAlive = 'set_player_alive';
  static const setGhostVoteUsed = 'set_ghost_vote_used';

  // NEW: day/night phase toggle, end-of-game character reveal, and
  // storyteller bluff list. Night/reveal are broadcast to everyone; the
  // bluff payload rides inside a normal chat_message (see
  // ChatMessage.bluffs) so it doesn't need its own wire type — this
  // constant is kept for clarity/future use.
  static const nightModeChange = 'night_mode_change';
  static const gameReveal = 'game_reveal';
  // NEW: Storyteller's final winner declaration at the end of a
  // revealed game. Broadcast to everyone (players + the ST's own
  // screen) as a one-shot popup — 'good' or 'evil'.
  static const gameWinner = 'game_winner';
  // NEW: the storyteller tapping one specific card open on the reveal
  // screen, broadcast live to the whole table. Split out from gameReveal
  // itself because gameReveal now only ever tells players WHO's on the
  // board (ids/seats) — never names or characters — precisely so a
  // player's device has nothing to leak before this message arrives.
  static const revealCardOpened = 'reveal_card_opened';
  static const bluffMessage = 'bluff_message';

  // NEW: direct, permission-less channel between a player and one of
  // their current seating neighbors — structurally identical to the
  // Storyteller DM (no accept/decline step, unaffected by chat lock or
  // mute), just player-to-player instead of player-to-storyteller. See
  // RoomState.neighborDmThreads / HostServer._handleNeighborDmMessage.
  static const neighborDmMessage = 'neighbor_dm_message';
  static const fabledUpdate = 'fabled_update';
}
