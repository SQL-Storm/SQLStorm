-- {"query": "7278.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1659} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        MAX(p.CreationDate) as LastPostDate,
        DATEDIFF('day', u.CreationDate, CURRENT_TIMESTAMP) as AccountAgeDays,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Elite'
            WHEN u.Reputation >= 1000 THEN 'Veteran'
            WHEN u.Reputation >= 100 THEN 'Regular'
            ELSE 'Newbie'
        END as RepTier,
        -- Complex window function to rank users by reputation within their tier
        ROW_NUMBER() OVER (PARTITION BY 
            CASE 
                WHEN u.Reputation >= 10000 THEN 'Elite'
                WHEN u.Reputation >= 1000 THEN 'Veteran'
                WHEN u.Reputation >= 100 THEN 'Regular'
                ELSE 'Newbie'
            END 
            ORDER BY u.Reputation DESC) as TierRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.CreationDate
),
PostComplexityAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        -- Calculate text complexity metrics
        LENGTH(p.Body) as BodyLength,
        (LENGTH(p.Body) - LENGTH(REPLACE(p.Body, '<', ''))) as HtmlTagCount,
        (LENGTH(p.Body) - LENGTH(REPLACE(p.Body, '&', ''))) as AmpersandCount,
        -- Extract and count tags using string manipulation
        CASE 
            WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 4 THEN 
                ARRAY_LENGTH(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), 1)
            ELSE 0 
        END as TagCount,
        -- Complex calculation for post quality score
        (p.Score * 1.5 + 
         COALESCE(p.ViewCount, 0) * 0.01 + 
         COALESCE(p.AnswerCount, 0) * 2.0 + 
         COALESCE(p.CommentCount, 0) * 0.5) as QualityScore,
        -- Determine if post is popular 
        CASE 
            WHEN (p.Score + COALESCE(p.ViewCount, 0)) > 1000 THEN 'Popular'
            WHEN (p.Score + COALESCE(p.ViewCount, 0)) > 100 THEN 'Moderate'
            ELSE 'Low'
        END as PopularityLevel,
        -- Find if this is a community wiki or has specific properties
        CASE 
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'CommunityWiki'
            WHEN p.PostTypeId = 4 OR p.PostTypeId = 5 THEN 'TagWiki'
            ELSE 'Regular'
        END as PostCategory
    FROM Posts p
    WHERE p.Id IS NOT NULL AND p.Body IS NOT NULL
),
UserPostPerformance AS (
    SELECT 
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.TotalPosts,
        uas.Questions,
        uas.Answers,
        uas.Comments,
        uas.TierRank,
        uas.RepTier,
        -- Aggregate post performance metrics
        AVG(pca.QualityScore) as AvgPostQuality,
        MAX(pca.QualityScore) as MaxPostQuality,
        SUM(pca.Score) as TotalScore,
        AVG(pca.Score) as AvgScore,
        COUNT(CASE WHEN pca.PostCategory = 'Popular' THEN 1 END) as PopularPosts,
        COUNT(CASE WHEN pca.PostCategory = 'TagWiki' THEN 1 END) as TagWikis,
        -- Calculate engagement ratios
        CASE 
            WHEN uas.TotalPosts > 0 THEN CAST(uas.Answers AS FLOAT) / uas.TotalPosts * 100 
            ELSE 0 
        END as AnswerRatio,
        CASE 
            WHEN uas.Questions > 0 THEN CAST(uas.Comments AS FLOAT) / uas.Questions * 100 
            ELSE 0 
        END as CommentRatio,
        -- Calculate post activity score relative to account age
        (uas.TotalPosts * 1.5 + uas.Answers * 2.0) / NULLIF(uas.AccountAgeDays, 0) as ActivityPerDay
    FROM UserActivityStats uas
    LEFT JOIN PostComplexityAnalysis pca ON uas.UserId = pca.OwnerUserId
    GROUP BY uas.UserId, uas.DisplayName, uas.Reputation, uas.TotalPosts, 
             uas.Questions, uas.Answers, uas.Comments, uas.TierRank, uas.RepTier, uas.AccountAgeDays
)
SELECT 
    upp.UserId,
    upp.DisplayName,
    upp.Reputation,
    upp.RepTier,
    upp.TierRank,
    upp.TotalPosts,
    upp.Questions,
    upp.Answers,
    upp.Comments,
    upp.AvgPostQuality,
    upp.MaxPostQuality,
    upp.TotalScore,
    upp.AvgScore,
    upp.PopularPosts,
    upp.TagWikis,
    upp.AnswerRatio,
    upp.CommentRatio,
    upp.ActivityPerDay,
    -- Complex conditional logic with multiple conditions and calculations
    CASE 
        WHEN upp.Reputation >= 10000 AND upp.AnswerRatio > 50 AND upp.ActivityPerDay > 0.5 THEN 'Top Performer'
        WHEN upp.Reputation >= 1000 AND upp.AnswerRatio > 30 AND upp.ActivityPerDay > 0.3 THEN 'Solid Contributor'
        WHEN upp.Reputation >= 100 AND upp.Answers > 10 AND upp.ActivityPerDay > 0.1 THEN 'Active Member'
        ELSE 'Regular User'
    END as ContributorTier,
    -- Calculate user engagement index
    ((upp.AvgPostQuality + upp.TotalScore) * 1.2 + 
     upp.Answers * 10 + upp.Comments * 5 + 
     COALESCE(upp.MaxPostQuality, 0) * 0.8) as EngagementIndex,
    -- Rank users for different performance metrics
    RANK() OVER (ORDER BY upp.TotalScore DESC) as ScoreRank,
    RANK() OVER (ORDER BY upp.ActivityPerDay DESC) as ActivityRank,
    RANK() OVER (ORDER BY upp.EngagementIndex DESC) as EngagementRank,
    -- Calculate percentile ranks for various metrics
    PERCENT_RANK() OVER (ORDER BY upp.TotalScore) * 100 as ScorePercentile,
    PERCENT_RANK() OVER (ORDER BY upp.ActivityPerDay) * 100 as ActivityPercentile
FROM UserPostPerformance upp
WHERE upp.TotalPosts > 0
    AND upp.Reputation IS NOT NULL
    AND upp.RepTier IS NOT NULL
    AND upp.TierRank IS NOT NULL
ORDER BY upp.ScoreRank, upp.ActivityPercentile DESC
LIMIT 1000;