# StreamyStats Recommendation System Improvements

## Overview

This document outlines the significant improvements made to the StreamyStats recommendation system to provide more accurate, contextual, and personalized content suggestions.

## New Features

### 1. **Temporal Decay & Recency Weighting**

**What it does**: Gives more weight to recently watched content when generating recommendations.

**How it works**:
- Calculates the time since each movie was watched
- Applies exponential decay (6-month half-life) to weight recent views higher
- Combines completion percentage with temporal weight for better taste profiling

**Benefits**:
- Recommendations reflect your current interests, not just historical preferences
- Adapts to changing viewing habits over time
- Seasonal content preferences are better captured

### 2. **Genre Preference Learning**

**What it does**: Analyzes your genre watching patterns and boosts recommendations for your preferred genres.

**How it works**:
- Tracks which genres you watch most (weighted by completion and recency)
- Calculates preference scores for each genre (0-1 scale)
- Applies up to 15% boost to recommendations matching your top genres

**Benefits**:
- More targeted recommendations based on your actual preferences
- Discovers new content within your favorite genres
- Balances exploration with personalization

### 3. **Context-Aware Recommendations**

**What it does**: Provides smart recommendations based on viewing time, day of week, and viewing patterns.

**Context Types**:
- **Auto**: Automatically detects current context (weekend/weekday/evening)
- **Weekend**: Content typically watched during weekends
- **Weekday**: Shorter content for busy weekdays
- **Evening**: Content preferred during evening hours
- **Quick Watch**: Short-form content (under 90 minutes)

**How it works**:
- Analyzes your historical viewing patterns by time/day
- Calculates average runtime preferences for each context
- Identifies genre and content type preferences by context
- Applies contextual filtering and boosting to recommendations

**Benefits**:
- "Quick watch" recommendations for busy schedules
- Weekend movie marathons vs. weekday episode viewing
- Time-appropriate content suggestions

### 4. **Enhanced UI with Multiple Recommendation Types**

**New Interface Features**:
- **Three recommendation tabs**: Standard, Smart Context, Genre Focused
- **Loading states** for seamless experience
- **Algorithm transparency**: Shows why each item was recommended
- **Enhanced tooltips**: Explains the recommendation logic

**Visual Indicators**:
- 🕒 Smart Context Match: Time-based recommendations
- 🎭 Genre-Enhanced: Genre preference boosted items
- "Based on" badges showing influencing movies

## Technical Implementation

### Backend Changes

#### New Functions in `SessionAnalysis` module:

1. **`find_contextual_recommendations/2`**
   - Context-aware recommendation engine
   - Analyzes viewing patterns by time/day
   - Supports multiple context types

2. **`weighted_average_embeddings_with_temporal/2`**
   - Combines completion percentage and temporal weights
   - Creates more accurate user taste profiles

3. **`calculate_user_genre_preferences/2`**
   - Genre preference analysis
   - Weighted by engagement and recency

4. **Context Analysis Functions**:
   - `determine_current_context/0`
   - `get_user_contextual_patterns/2`
   - `matches_context?/2`

#### New API Endpoints:

- `GET /servers/:id/statistics/recommendations/contextual`
- `GET /servers/:id/statistics/recommendations/genre-boosted`

### Frontend Changes

#### Enhanced Components:

1. **`SimilarStatstics.tsx`**:
   - Multi-tab interface for different recommendation types
   - Dynamic loading of recommendation types
   - Enhanced recommendation explanations

2. **`similar-statistics.ts`**:
   - `getContextualRecommendations()` function
   - `getGenreBoostedRecommendations()` function
   - Proper caching strategies for each type

## Performance Optimizations

### Caching Strategy:
- **Standard recommendations**: 1 hour cache
- **Contextual recommendations**: 30 minutes cache (changes with time)
- **Genre-boosted recommendations**: 2 hours cache
- **ETS-based in-memory caching** for frequently accessed data

### Query Optimizations:
- Fetch 2x requested items for genre boosting, then filter
- Efficient temporal weight calculations
- Optimized similarity queries with proper indexing

## Algorithm Details

### Recommendation Scoring:

#### Standard Algorithm:
```
score = embedding_similarity * (0.5 + completion_weight * 0.3 + temporal_weight * 0.2)
```

#### Genre-Boosted Algorithm:
```
score = standard_score * (1.0 + genre_boost)
genre_boost = avg(user_preference_for_item_genres) * 0.15
```

#### Contextual Algorithm:
```
score = standard_score * (1.0 + context_score)
context_score = runtime_match + genre_context_match + type_preference_match
```

### Weighting Factors:

- **Completion percentage**: 0-1 (how much of the content was watched)
- **Temporal weight**: exponential decay over 6 months
- **Genre preference**: 0-1 based on viewing history
- **Context bonus**: up to 30% boost for contextually appropriate content

## Usage Examples

### API Usage:

```bash
# Get standard recommendations
GET /servers/1/statistics/recommendations/me?limit=20

# Get contextual recommendations
GET /servers/1/statistics/recommendations/contextual?context=weekend&limit=20

# Get genre-boosted recommendations  
GET /servers/1/statistics/recommendations/genre-boosted?limit=20
```

### Frontend Usage:

```typescript
// Standard recommendations (existing)
const recommendations = await getSimilarStatistics(serverId);

// Contextual recommendations
const contextual = await getContextualRecommendations(serverId, "evening");

// Genre-boosted recommendations
const genreBoosted = await getGenreBoostedRecommendations(serverId);
```

## Future Enhancement Opportunities

### 1. **Social Recommendations**
- "Users like you also watched" algorithm
- Collaborative filtering based on similar viewing patterns
- Community-driven recommendation scores

### 2. **Mood-Based Filtering**
- Manual mood selection (action, comedy, drama, etc.)
- Time-of-day mood detection
- Seasonal mood adjustments

### 3. **Content Freshness**
- Boost newly added content
- Balance between familiar and new recommendations
- "Trending on your server" features

### 4. **Multi-User Households**
- Family-friendly recommendations
- Merge preferences for shared viewing
- Individual vs. household recommendation modes

### 5. **Advanced Contextual Features**
- Weather-based recommendations
- Holiday/special event suggestions
- Binge-watching vs. single-episode detection

### 6. **Machine Learning Enhancements**
- Deep learning models for better embeddings
- Reinforcement learning from user feedback
- A/B testing framework for algorithm improvements

### 7. **Cross-Media Recommendations**
- Movie → TV series suggestions
- Book → movie adaptations
- Franchise-aware recommendations

## Configuration Options

### Server Settings:
```elixir
# Enable/disable features
boost_user_genres: true/false
enable_contextual: true/false
temporal_decay_days: 180 (default)
max_genre_boost: 0.15 (default)
```

### Frontend Settings:
```typescript
// Default recommendation type
defaultRecommendationType: "standard" | "contextual" | "genre-boosted"

// Cache durations
cacheStandard: 60 * 60 (1 hour)
cacheContextual: 60 * 30 (30 minutes)  
cacheGenreBoosted: 60 * 60 * 2 (2 hours)
```

## Monitoring & Analytics

### Metrics to Track:
- Recommendation click-through rates by algorithm type
- User engagement with different recommendation types
- Genre preference accuracy over time
- Contextual recommendation relevance scores

### Debug Functions:
- `StreamystatServer.Debug.diagnose_recommendations/1`
- Cache performance monitoring
- Algorithm performance comparison tools

This enhanced recommendation system provides a more intelligent, personalized, and context-aware content discovery experience for StreamyStats users. 