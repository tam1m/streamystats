/**
 * Migration script to rename session fields from:
 * - item_jellyfin_id -> remove (use item_id instead)
 * - series_jellyfin_id -> series_id
 * - season_jellyfin_id -> season_id
 *
 * Run this script to update existing database schema.
 * Note: This is a manual migration for the field name changes.
 */
declare function migrateSessionFields(): Promise<void>;
export { migrateSessionFields };
//# sourceMappingURL=migrate-session-fields.d.ts.map