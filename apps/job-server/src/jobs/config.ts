import OpenAI from "openai";

// Initialize OpenAI client (optional)
export const openai = process.env.OPENAI_API_KEY
  ? new OpenAI({
      apiKey: process.env.OPENAI_API_KEY,
    })
  : null;

// Configuration constants
export const OPENAI_CONFIG = {
  EMBEDDING_MODEL: "text-embedding-3-small",
  EMBEDDING_DIMENSIONS: 1536,
  MAX_TEXT_LENGTH: 8000,
  MAX_RETRIES: 3,
  RETRY_DELAY: 1000, // 1 second base delay
  RATE_LIMIT_DELAY: 500, // 0.5 second delay between requests
} as const;

// Timeout configurations
export const TIMEOUT_CONFIG = {
  DEFAULT: 30000, // 30 seconds
  ITEMS_SYNC: 60000, // 60 seconds for large item syncs
} as const;
