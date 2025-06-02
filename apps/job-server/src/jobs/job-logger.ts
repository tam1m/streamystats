import { db, jobResults, NewJobResult } from "@streamystats/database";

// Helper function to log job results
export async function logJobResult(
  jobId: string,
  jobName: string,
  status: "completed" | "failed" | "processing",
  result: any,
  processingTime: number,
  error?: any
) {
  try {
    const jobResult: NewJobResult = {
      jobId,
      jobName,
      status,
      result: result ? JSON.parse(JSON.stringify(result)) : null,
      error: error ? error.message || String(error) : null,
      processingTime,
    };

    await db.insert(jobResults).values(jobResult);
  } catch (err) {
    console.error("Failed to log job result:", err);
  }
}
