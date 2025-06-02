"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.TIMEOUT_CONFIG = exports.OPENAI_CONFIG = exports.openai = void 0;
const openai_1 = __importDefault(require("openai"));
// Initialize OpenAI client (optional)
exports.openai = process.env.OPENAI_API_KEY
    ? new openai_1.default({
        apiKey: process.env.OPENAI_API_KEY,
    })
    : null;
// Configuration constants
exports.OPENAI_CONFIG = {
    EMBEDDING_MODEL: "text-embedding-3-small",
    EMBEDDING_DIMENSIONS: 1536,
    MAX_TEXT_LENGTH: 8000,
    MAX_RETRIES: 3,
    RETRY_DELAY: 1000, // 1 second base delay
    RATE_LIMIT_DELAY: 500, // 0.5 second delay between requests
};
// Timeout configurations
exports.TIMEOUT_CONFIG = {
    DEFAULT: 30000, // 30 seconds
    ITEMS_SYNC: 60000, // 60 seconds for large item syncs
};
