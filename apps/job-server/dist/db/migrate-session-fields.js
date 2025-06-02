"use strict";
/**
 * Migration script to rename session fields from:
 * - item_jellyfin_id -> remove (use item_id instead)
 * - series_jellyfin_id -> series_id
 * - season_jellyfin_id -> season_id
 *
 * Run this script to update existing database schema.
 * Note: This is a manual migration for the field name changes.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.migrateSessionFields = migrateSessionFields;
const drizzle_orm_1 = require("drizzle-orm");
const connection_1 = require("./connection");
async function migrateSessionFields() {
    console.log("🔄 Starting session fields migration...");
    try {
        // Check if old columns exist before attempting migration
        const checkColumns = await connection_1.db.execute((0, drizzle_orm_1.sql) `
      SELECT column_name 
      FROM information_schema.columns 
      WHERE table_name = 'sessions' 
      AND column_name IN ('item_jellyfin_id', 'series_jellyfin_id', 'season_jellyfin_id')
    `);
        if (checkColumns.length === 0) {
            console.log("✅ Migration not needed - fields already updated");
            return;
        }
        console.log(`📋 Found ${checkColumns.length} columns to migrate`);
        await connection_1.db.transaction(async (tx) => {
            // First, copy item_jellyfin_id data to item_id if item_id is null
            if (checkColumns.some((col) => col.column_name === "item_jellyfin_id")) {
                console.log("📝 Updating item_id field...");
                await tx.execute((0, drizzle_orm_1.sql) `
          UPDATE sessions 
          SET item_id = item_jellyfin_id 
          WHERE item_id IS NULL AND item_jellyfin_id IS NOT NULL
        `);
                // Drop the old column
                await tx.execute((0, drizzle_orm_1.sql) `ALTER TABLE sessions DROP COLUMN IF EXISTS item_jellyfin_id`);
            }
            // Rename series_jellyfin_id to series_id
            if (checkColumns.some((col) => col.column_name === "series_jellyfin_id")) {
                console.log("📝 Renaming series_jellyfin_id to series_id...");
                await tx.execute((0, drizzle_orm_1.sql) `ALTER TABLE sessions RENAME COLUMN series_jellyfin_id TO series_id`);
            }
            // Rename season_jellyfin_id to season_id
            if (checkColumns.some((col) => col.column_name === "season_jellyfin_id")) {
                console.log("📝 Renaming season_jellyfin_id to season_id...");
                await tx.execute((0, drizzle_orm_1.sql) `ALTER TABLE sessions RENAME COLUMN season_jellyfin_id TO season_id`);
            }
        });
        console.log("✅ Session fields migration completed successfully!");
    }
    catch (error) {
        console.error("❌ Migration failed:", error);
        throw error;
    }
}
// Run the migration if this file is executed directly
if (require.main === module) {
    migrateSessionFields()
        .then(() => {
        console.log("🎉 Migration completed!");
        process.exit(0);
    })
        .catch((error) => {
        console.error("💥 Migration failed:", error);
        process.exit(1);
    });
}
//# sourceMappingURL=migrate-session-fields.js.map