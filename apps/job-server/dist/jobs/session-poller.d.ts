import { ActiveSessionResponse } from "../jellyfin/types";
interface SessionPollerConfig {
    intervalMs?: number;
    enabled?: boolean;
}
declare class SessionPoller {
    private trackedSessions;
    private intervalId;
    private config;
    constructor(config?: SessionPollerConfig);
    /**
     * Start the session poller
     */
    start(): Promise<void>;
    /**
     * Stop the session poller
     */
    stop(): void;
    /**
     * Get active sessions for a specific server
     */
    getActiveSessions(serverId: number): ActiveSessionResponse[];
    /**
     * Poll all servers for session updates
     */
    private pollSessions;
    /**
     * List all active servers
     */
    private listServers;
    /**
     * Poll sessions for a specific server
     */
    private pollServer;
    /**
     * Process sessions for a server
     */
    private processSessions;
    /**
     * Filter out invalid sessions (trailers, prerolls, etc.)
     */
    private filterValidSessions;
    /**
     * Detect changes between current and tracked sessions
     */
    private detectSessionChanges;
    /**
     * Generate a unique session key
     */
    private generateSessionKey;
    /**
     * Convert sessions array to a map keyed by session key
     */
    private sessionsToMap;
    /**
     * Handle new sessions
     */
    private handleNewSessions;
    /**
     * Handle updated sessions
     */
    private handleUpdatedSessions;
    /**
     * Handle ended sessions
     */
    private handleEndedSessions;
    /**
     * Calculate play duration based on session state
     */
    private calculateDuration;
    /**
     * Save playback record to database
     */
    private savePlaybackRecord;
    /**
     * Parse Jellyfin date string to Date object
     */
    private parseJellyfinDate;
    /**
     * Format ticks as time string
     */
    private formatTicksAsTime;
    /**
     * Pad time component with leading zero
     */
    private padTime;
    /**
     * Update configuration
     */
    updateConfig(config: Partial<SessionPollerConfig>): void;
    /**
     * Get poller status
     */
    getStatus(): {
        enabled: boolean;
        intervalMs: number;
        isRunning: boolean;
        trackedServers: number;
        totalTrackedSessions: number;
    };
}
export declare const sessionPoller: SessionPoller;
export { SessionPoller, SessionPollerConfig };
//# sourceMappingURL=session-poller.d.ts.map