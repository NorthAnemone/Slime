# Online and proximity-voice roadmap

Build 0.12 keeps the host-authoritative simulation and all replicated player positions independent from ENet-specific UI. That is the seam for a later Steam transport.

## Recommended sequence

1. Add Steamworks to a separate feature branch and wrap session creation behind a `SessionProvider` interface. Keep the current offline and direct-IP providers for development.
2. Implement friends-only and public Steam lobbies. Store floor seed, build protocol version, privacy and open slots as lobby metadata. Nominate the lobby owner as the listen-server host.
3. Replace internet ENet packets with Steam Networking Sockets/Datagram Relay while leaving the existing RPC and authoritative simulation model intact. Relay traffic protects player IP addresses and improves NAT traversal.
4. Add proximity voice after positional networking is stable. Capture compressed Steam Voice frames, relay them unreliably, and attenuate playback from the replicated speaker-to-listener distance. Include push-to-talk, mute, input/output selection, volume, accessibility indicators and moderation controls from the first release.
5. Add dedicated servers only after persistence, reconnects, host migration, server-side saves, abuse controls and load tests exist. Friends-only listen servers are the smaller first milestone.

Official references:

- Steam Matchmaking & Lobbies: https://partner.steamgames.com/doc/features/multiplayer/matchmaking
- Steam Datagram Relay: https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay
- Steam Voice: https://partner.steamgames.com/doc/features/voice

Proximity chat is intentionally not simulated in build 0.12: microphone capture and network transmission need consent, mute/moderation UX, device handling and an authenticated online identity. The current position snapshots already contain the distance information its mixer will need.
