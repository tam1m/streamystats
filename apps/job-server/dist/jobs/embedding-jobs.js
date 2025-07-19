"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateItemEmbeddingsJob = generateItemEmbeddingsJob;
const database_1 = require("@streamystats/database");
const axios_1 = __importDefault(require("axios"));
const drizzle_orm_1 = require("drizzle-orm");
const openai_1 = __importDefault(require("openai"));
const config_1 = require("./config");
const job_logger_1 = require("./job-logger");
const queue_1 = require("./queue");
// Job: Generate embeddings for media items using different providers
async function generateItemEmbeddingsJob(job) {
    const startTime = Date.now();
    const { serverId, provider, config } = job.data;
    let lastHeartbeat = Date.now();
    try {
        // Validate provider early
        if (!provider) {
            throw new Error("Embedding provider not configured. Please select either 'openai' or 'ollama' in the server settings.");
        }
        console.log(`Generating embeddings for movies and series on server ${serverId} using ${provider}`);
        // Update job status to processing
        await (0, job_logger_1.logJobResult)(job.id, "generate-item-embeddings", "processing", { serverId, provider, status: "starting" }, Date.now() - startTime);
        // Get unprocessed items (Movies and Series) for this server
        const unprocessedItems = await database_1.db
            .select()
            .from(database_1.items)
            .where((0, drizzle_orm_1.and)((0, drizzle_orm_1.eq)(database_1.items.serverId, serverId), (0, drizzle_orm_1.eq)(database_1.items.processed, false), (0, drizzle_orm_1.sql) `${database_1.items.type} IN ('Movie', 'Series')`))
            .limit(100); // Process in batches
        if (unprocessedItems.length === 0) {
            await (0, job_logger_1.logJobResult)(job.id, "generate-item-embeddings", "completed", { serverId, provider, processed: 0, message: "No items to process" }, Date.now() - startTime);
            return { success: true, processed: 0 };
        }
        let processedCount = 0;
        let errorCount = 0;
        // Helper function to send heartbeat every 30 seconds
        const sendHeartbeat = async () => {
            const now = Date.now();
            if (now - lastHeartbeat > 30000) {
                // 30 seconds
                await (0, job_logger_1.logJobResult)(job.id, "generate-item-embeddings", "processing", {
                    serverId,
                    provider,
                    status: "processing",
                    processed: processedCount,
                    total: unprocessedItems.length,
                    lastHeartbeat: new Date().toISOString(),
                }, now - startTime);
                lastHeartbeat = now;
                console.log(`Embedding job heartbeat: ${processedCount}/${unprocessedItems.length} processed`);
            }
        };
        // Helper function to prepare text for embedding
        const prepareTextForEmbedding = (item) => {
            const textParts = [
                item.name,
                item.overview,
                item.type,
                item.officialRating,
                item.premiereDate,
                item.communityRating,
                item.productionYear,
                item.seriesStudio,
                item.runtimeTicks,
                item.seriesName,
                ...(item.genres || []),
            ].filter(Boolean);
            // Add people data if available (actors, directors, etc.)
            if (item.people) {
                try {
                    const peopleData = typeof item.people === "string"
                        ? JSON.parse(item.people)
                        : item.people;
                    if (peopleData && typeof peopleData === "object") {
                        const peopleNames = Object.values(peopleData)
                            .filter((person) => person && person.Name)
                            .map((person) => {
                            // Include both name and role for better context
                            const parts = [person.Name];
                            if (person.Role && person.Type === "Actor") {
                                parts.push(`as ${person.Role}`);
                            }
                            if (person.Type && person.Type !== "Actor") {
                                parts.push(`(${person.Type})`);
                            }
                            return parts.join(" ");
                        });
                        textParts.push(...peopleNames);
                    }
                }
                catch (error) {
                    // Silently continue if people data can't be parsed
                    console.warn(`Failed to parse people data for item ${item.id}:`, error);
                }
            }
            return textParts.join(" ").substring(0, config_1.OPENAI_CONFIG.MAX_TEXT_LENGTH);
        };
        if (provider === "openai") {
            if (!config.openaiApiKey) {
                throw new Error("OpenAI API key not provided");
            }
            const openaiClient = new openai_1.default({
                apiKey: config.openaiApiKey,
                timeout: config_1.TIMEOUT_CONFIG.DEFAULT,
                maxRetries: config_1.OPENAI_CONFIG.MAX_RETRIES,
            });
            // Process items in batches for OpenAI
            const BATCH_SIZE = 20; // OpenAI supports up to 2048 inputs, but 20 is a good balance
            for (let i = 0; i < unprocessedItems.length; i += BATCH_SIZE) {
                const batch = unprocessedItems.slice(i, i + BATCH_SIZE);
                try {
                    // Send heartbeat if needed
                    await sendHeartbeat();
                    // Prepare all texts for the batch
                    const batchData = batch
                        .map((item) => {
                        const textToEmbed = prepareTextForEmbedding(item);
                        return textToEmbed.trim() ? { item, textToEmbed } : null;
                    })
                        .filter(Boolean);
                    if (batchData.length === 0) {
                        continue; // Skip if no valid texts in this batch
                    }
                    // Extract just the texts for the API call
                    const textsToEmbed = batchData.map((data) => data.textToEmbed);
                    console.log(`Processing OpenAI batch: ${batchData.length} items`);
                    // Call OpenAI API with batch of texts
                    const response = await openaiClient.embeddings.create({
                        model: config_1.OPENAI_CONFIG.EMBEDDING_MODEL,
                        input: textsToEmbed,
                        dimensions: config_1.OPENAI_CONFIG.EMBEDDING_DIMENSIONS,
                    });
                    // Validate response structure
                    if (!response.data || response.data.length !== batchData.length) {
                        throw new Error(`Invalid response structure from OpenAI API: expected ${batchData.length} embeddings, got ${response.data?.length || 0}`);
                    }
                    // Process each embedding in the batch
                    for (let j = 0; j < batchData.length; j++) {
                        const { item } = batchData[j];
                        const embeddingData = response.data[j];
                        if (!embeddingData || !embeddingData.embedding) {
                            console.error(`No embedding data for item ${item.id}`);
                            errorCount++;
                            continue;
                        }
                        const rawEmbedding = embeddingData.embedding;
                        // Validate embedding dimensions
                        if (!Array.isArray(rawEmbedding) || rawEmbedding.length === 0) {
                            console.error(`Invalid embedding data for item ${item.id}`);
                            errorCount++;
                            continue;
                        }
                        let embedding;
                        // Ensure embedding has correct dimensions
                        if (rawEmbedding.length !== config_1.OPENAI_CONFIG.EMBEDDING_DIMENSIONS) {
                            console.warn(`OpenAI embedding dimension mismatch for item ${item.id}: expected ${config_1.OPENAI_CONFIG.EMBEDDING_DIMENSIONS}, got ${rawEmbedding.length}`);
                            // Normalize dimensions to match expected size
                            if (rawEmbedding.length < config_1.OPENAI_CONFIG.EMBEDDING_DIMENSIONS) {
                                // Pad with zeros
                                embedding = [
                                    ...rawEmbedding,
                                    ...new Array(config_1.OPENAI_CONFIG.EMBEDDING_DIMENSIONS - rawEmbedding.length).fill(0),
                                ];
                            }
                            else if (rawEmbedding.length > config_1.OPENAI_CONFIG.EMBEDDING_DIMENSIONS) {
                                // Truncate
                                embedding = rawEmbedding.slice(0, config_1.OPENAI_CONFIG.EMBEDDING_DIMENSIONS);
                            }
                            else {
                                embedding = rawEmbedding;
                            }
                        }
                        else {
                            embedding = rawEmbedding;
                        }
                        // Update item with embedding
                        try {
                            await database_1.db
                                .update(database_1.items)
                                .set({
                                embedding: embedding,
                                processed: true,
                            })
                                .where((0, drizzle_orm_1.eq)(database_1.items.id, item.id));
                            processedCount++;
                        }
                        catch (dbError) {
                            console.error(`Database error for item ${item.id}:`, dbError);
                            errorCount++;
                        }
                    }
                    // Add delay between batches (not between individual items)
                    await new Promise((resolve) => setTimeout(resolve, config_1.OPENAI_CONFIG.RATE_LIMIT_DELAY));
                }
                catch (batchError) {
                    console.error(`Error processing OpenAI batch starting at index ${i}:`, batchError);
                    // Handle specific OpenAI errors
                    if (batchError instanceof Error) {
                        if (batchError.message.includes("rate_limit")) {
                            throw new Error(`OpenAI rate limit exceeded. Please try again later.`);
                        }
                        else if (batchError.message.includes("insufficient_quota")) {
                            throw new Error(`OpenAI quota exceeded. Please check your billing.`);
                        }
                        else if (batchError.message.includes("invalid_api_key")) {
                            throw new Error(`Invalid OpenAI API key. Please check your configuration.`);
                        }
                    }
                    // For other errors, mark all items in batch as errors and continue
                    errorCount += batch.length;
                    continue;
                }
            }
        }
        else if (provider === "ollama") {
            // Keep Ollama processing unchanged - process items one by one
            for (const item of unprocessedItems) {
                try {
                    // Send heartbeat if needed
                    await sendHeartbeat();
                    const textToEmbed = prepareTextForEmbedding(item);
                    if (!textToEmbed.trim()) {
                        // Skip items without meaningful text
                        continue;
                    }
                    if (!config.ollamaBaseUrl || !config.ollamaModel) {
                        throw new Error("Ollama configuration incomplete");
                    }
                    const headers = {
                        "Content-Type": "application/json",
                    };
                    if (config.ollamaApiToken) {
                        headers["Authorization"] = `Bearer ${config.ollamaApiToken}`;
                    }
                    const response = await axios_1.default.post(`${config.ollamaBaseUrl}/api/embeddings`, {
                        model: config.ollamaModel,
                        prompt: textToEmbed,
                    }, {
                        headers,
                        timeout: config_1.TIMEOUT_CONFIG.DEFAULT,
                    });
                    let rawEmbedding = response.data.embedding || response.data.embeddings;
                    if (!rawEmbedding) {
                        throw new Error("No embedding returned from Ollama");
                    }
                    let embedding;
                    // Ensure we have the right dimensions (pad or truncate to match OPENAI_CONFIG.EMBEDDING_DIMENSIONS)
                    if (rawEmbedding.length < config_1.OPENAI_CONFIG.EMBEDDING_DIMENSIONS) {
                        // Pad with zeros
                        embedding = [
                            ...rawEmbedding,
                            ...new Array(config_1.OPENAI_CONFIG.EMBEDDING_DIMENSIONS - rawEmbedding.length).fill(0),
                        ];
                    }
                    else if (rawEmbedding.length > config_1.OPENAI_CONFIG.EMBEDDING_DIMENSIONS) {
                        // Truncate
                        embedding = rawEmbedding.slice(0, config_1.OPENAI_CONFIG.EMBEDDING_DIMENSIONS);
                    }
                    else {
                        embedding = rawEmbedding;
                    }
                    // Update item with embedding
                    await database_1.db
                        .update(database_1.items)
                        .set({
                        embedding: embedding,
                        processed: true,
                    })
                        .where((0, drizzle_orm_1.eq)(database_1.items.id, item.id));
                    processedCount++;
                    // Ollama is typically self-hosted, use shorter delay
                    await new Promise((resolve) => setTimeout(resolve, 100)); // 0.1 second delay
                }
                catch (itemError) {
                    console.error(`Error processing item ${item.id}:`, itemError);
                    errorCount++;
                    // Continue processing other items even if one fails
                    continue;
                }
            }
        }
        else {
            throw new Error(`Unsupported provider: ${provider}`);
        }
        const processingTime = Date.now() - startTime;
        await (0, job_logger_1.logJobResult)(job.id, "generate-item-embeddings", "completed", { serverId, provider, processed: processedCount, errors: errorCount }, processingTime);
        // If there are more items to process, queue another job
        const remainingItems = await database_1.db
            .select({ count: database_1.items.id })
            .from(database_1.items)
            .where((0, drizzle_orm_1.and)((0, drizzle_orm_1.eq)(database_1.items.serverId, serverId), (0, drizzle_orm_1.eq)(database_1.items.processed, false), (0, drizzle_orm_1.sql) `${database_1.items.type} IN ('Movie', 'Series')`));
        if (remainingItems.length > 0) {
            console.log(`Queueing next batch for server ${serverId}, ${remainingItems.length} items remaining`);
            // Queue next batch using the job queue directly (more efficient than HTTP call)
            try {
                const boss = await (0, queue_1.getJobQueue)();
                const nextJobId = await boss.send("generate-item-embeddings", {
                    serverId,
                    provider,
                    config,
                }, {
                    retryLimit: 3,
                    retryDelay: 30, // 30 seconds
                });
                console.log(`Successfully queued next embedding batch with job ID: ${nextJobId}`);
            }
            catch (queueError) {
                console.error("Failed to queue next embedding batch directly, falling back to HTTP call:", queueError);
                // Fallback to HTTP call if direct queueing fails
                setTimeout(async () => {
                    try {
                        // Construct job server URL with proper fallback
                        const jobServerUrl = process.env.JOB_SERVER_URL &&
                            process.env.JOB_SERVER_URL !== "undefined"
                            ? process.env.JOB_SERVER_URL
                            : "http://localhost:3005";
                        const response = await fetch(`${jobServerUrl}/api/jobs/start-embedding`, {
                            method: "POST",
                            headers: {
                                "Content-Type": "application/json",
                            },
                            body: JSON.stringify({ serverId }),
                        });
                        if (!response.ok) {
                            console.error(`Failed to queue next embedding batch via HTTP: ${response.statusText}`);
                        }
                        else {
                            console.log("Successfully queued next embedding batch via HTTP fallback");
                        }
                    }
                    catch (httpError) {
                        console.error("Error in HTTP fallback for queueing next embedding batch:", httpError);
                    }
                }, 1000); // 1 second delay
            }
        }
        return { success: true, processed: processedCount, errors: errorCount };
    }
    catch (error) {
        const processingTime = Date.now() - startTime;
        console.error(`Embedding job failed for server ${serverId}:`, error);
        await (0, job_logger_1.logJobResult)(job.id, "generate-item-embeddings", "failed", {
            serverId,
            provider,
            error: error instanceof Error ? error.message : String(error),
            processed: 0, // Include what was processed before failure
        }, processingTime, error);
        throw error;
    }
}
