"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.logJobResult = logJobResult;
const database_1 = require("@streamystats/database");
// Helper function to log job results
async function logJobResult(jobId, jobName, status, result, processingTime, error) {
    try {
        const jobResult = {
            jobId,
            jobName,
            status,
            result: result ? JSON.parse(JSON.stringify(result)) : null,
            error: error ? error.message || String(error) : null,
            processingTime,
        };
        await database_1.db.insert(database_1.jobResults).values(jobResult);
    }
    catch (err) {
        console.error("Failed to log job result:", err);
    }
}
