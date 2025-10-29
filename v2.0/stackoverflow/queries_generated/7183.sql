-- {"query": "7183.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2700} 
WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS TotalPosts,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS Questions,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS Answers,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        MAX(p.CreationDate) AS LastPostDate,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS AvgAnswerScore,
        COUNT(DISTINCT p.Tags) AS UniqueTagsUsed
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        TotalPosts,
        Questions,
        Answers,
        TotalQuestionScore,
        TotalAnswerScore,
        LastPostDate,
        AvgQuestionScore,
        AvgAnswerScore,
        UniqueTagsUsed,
        ROW_NUMBER() OVER (ORDER BY TotalQuestionScore DESC, TotalAnswerScore DESC) AS RankByScore,
        ROW_NUMBER() OVER (ORDER BY TotalPosts DESC) AS RankByPosts
    FROM UserPostStats
),
BadgeSummary AS (
    SELECT 
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        STRING_AGG(b.Name, ', ') AS BadgeNames,
        MIN(b.Date) AS FirstBadgeDate,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
PostActivity AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.ParentId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Tags,
        -- Calculate time since last activity
        EXTRACT(DAY FROM (NOW() - p.LastActivityDate)) AS DaysSinceLastActivity,
        -- Extract tags for complex manipulation
        ARRAY_TO_STRING(STRING_TO_ARRAY(p.Tags, '<'), ', ') AS ReformattedTags,
        -- Determine if post is popular based on score and views
        CASE 
            WHEN (p.Score > 100 OR p.ViewCount > 5000) THEN 'Popular'
            WHEN (p.Score > 50 OR p.ViewCount > 1000) THEN 'Moderate'
            ELSE 'Low'
        END AS PopularityLevel,
        -- Calculate reputation impact score
        p.Score * (CASE WHEN p.PostTypeId = 1 THEN 1.5 ELSE 1 END) AS ReputationImpactScore
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Only questions and answers
),
PostWithUserDetails AS (
    SELECT 
        pa.PostId,
        pa.PostTypeId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.CreationDate,
        pa.OwnerUserId,
        pa.ParentId,
        pa.AnswerCount,
        pa.CommentCount,
        pa.FavoriteCount,
        pa.Tags,
        pa.DaysSinceLastActivity,
        pa.ReformattedTags,
        pa.PopularityLevel,
        pa.ReputationImpactScore,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation
    FROM PostActivity pa
    LEFT JOIN Users u ON pa.OwnerUserId = u.Id
),
TagStatistics AS (
    SELECT 
        t.TagName,
        t.Count AS TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        -- Calculate percentage of total tags
        ROUND((t.Count * 100.0 / (SELECT SUM(Count) FROM Tags)), 2) AS TagPercentage,
        -- Determine tag type based on properties
        CASE 
            WHEN t.IsRequired = 1 THEN 'Required'
            WHEN t.IsModeratorOnly = 1 THEN 'Moderator Only'
            ELSE 'General'
        END AS TagType
    FROM Tags t
),
ComplexPostAnalysis AS (
    SELECT 
        p.PostId,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.ParentId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Tags,
        p.DaysSinceLastActivity,
        p.ReformattedTags,
        p.PopularityLevel,
        p.ReputationImpactScore,
        p.OwnerDisplayName,
        p.OwnerReputation,
        -- Calculate percentile rank of score within all posts
        PERCENT_RANK() OVER (ORDER BY p.Score) AS ScorePercentile,
        -- Calculate moving average of score for questions (over 30 posts)
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) OVER (
            ORDER BY p.CreationDate 
            ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
        ) AS MovingAvgScore30,
        -- Calculate how many posts created per day by user
        COUNT(*) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate 
                      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS UserPostCountToDate,
        -- Determine if post is a new answer (last 24 hours)
        CASE 
            WHEN p.PostTypeId = 2 
                 AND p.CreationDate >= NOW() - INTERVAL '1 day' 
                 THEN 'New Answer'
            ELSE 'Regular'
        END AS PostAgeCategory,
        -- Calculate complexity ratio (comments/answers ratio for questions)
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 
            THEN p.CommentCount * 1.0 / p.AnswerCount 
            ELSE NULL 
        END AS CommentAnswerRatio,
        -- Determine if it's a high-reputation user
        CASE WHEN p.OwnerReputation > 10000 THEN 1 ELSE 0 END AS HighReputationUser
    FROM PostWithUserDetails p
),
UserMetrics AS (
    SELECT 
        t.UserId,
        t.DisplayName,
        t.Reputation,
        t.TotalPosts,
        t.Questions,
        t.Answers,
        t.TotalQuestionScore,
        t.TotalAnswerScore,
        t.LastPostDate,
        t.AvgQuestionScore,
        t.AvgAnswerScore,
        t.UniqueTagsUsed,
        t.RankByScore,
        t.RankByPosts,
        COALESCE(b.TotalBadges, 0) AS TotalBadges,
        COALESCE(b.GoldBadges, 0) AS GoldBadges,
        COALESCE(b.SilverBadges, 0) AS SilverBadges,
        COALESCE(b.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(b.BadgeNames, '') AS BadgeNames,
        b.FirstBadgeDate,
        b.LastBadgeDate
    FROM TopUsers t
    LEFT JOIN BadgeSummary b ON t.UserId = b.UserId
)
SELECT 
    -- Main results with complex joins and transformations
    u.DisplayName,
    u.Reputation,
    u.TotalPosts,
    u.Questions,
    u.Answers,
    u.TotalQuestionScore,
    u.TotalAnswerScore,
    u.AvgQuestionScore,
    u.AvgAnswerScore,
    u.UniqueTagsUsed,
    u.RankByScore,
    u.RankByPosts,
    u.TotalBadges,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    CASE 
        WHEN u.TotalPosts > 100 THEN 'Veteran'
        WHEN u.TotalPosts > 10 THEN 'Regular'
        WHEN u.TotalPosts > 0 THEN 'Newbie'
        ELSE 'Inactive'
    END AS UserSeniority,
    COALESCE(
        (SELECT STRING_AGG(DISTINCT s.TagName, ', ')
         FROM TagStatistics s
         WHERE s.TagName IN (
             SELECT TRIM(UNNEST(STRING_TO_ARRAY(p.ReformattedTags, ',')))
             FROM ComplexPostAnalysis p
             WHERE p.OwnerUserId = u.UserId
             AND p.PostTypeId = 1
         )
         AND s.TagType = 'General'
        ), 
        'No General Tags'
    ) AS PopularGeneralTags,
    -- Complex aggregation with window functions
    (
        SELECT COUNT(*) 
        FROM ComplexPostAnalysis 
        WHERE OwnerUserId = u.UserId 
        AND PostAgeCategory = 'New Answer'
    ) AS NewAnswersLast24Hours,
    -- Correlated subquery with complex logic
    (
        SELECT ARRAY_AGG(DISTINCT c.PostId)
        FROM ComplexPostAnalysis c
        WHERE c.OwnerUserId = u.UserId 
        AND c.PopularityLevel = 'Popular'
        AND c.Score > 50
        ORDER BY c.Score DESC
        LIMIT 5
    ) AS PopularPostIds,
    -- Null handling and coalescing
    COALESCE(u.BadgeNames, 'No Badges') AS BadgeList,
    CASE WHEN u.FirstBadgeDate IS NULL THEN 'Never' ELSE TO_CHAR(u.FirstBadgeDate, 'YYYY-MM-DD') END AS FirstBadgeDate,
    CASE WHEN u.LastBadgeDate IS NULL THEN 'Never' ELSE TO_CHAR(u.LastBadgeDate, 'YYYY-MM-DD') END AS LastBadgeDate,
    -- Complex calculations
    ROUND(
        (
            (u.TotalQuestionScore + u.TotalAnswerScore) * 
            (CASE WHEN u.RankByScore <= 10 THEN 1.5 ELSE 1.0 END) *
            (CASE WHEN u.TotalBadges > 0 THEN 1.2 ELSE 1.0 END)
        ), 2
    ) AS OverallUserScore,
    -- Set operator: using UNION to create multiple result sets
    (
        SELECT COUNT(*) 
        FROM ComplexPostAnalysis 
        WHERE OwnerUserId = u.UserId
        AND PostTypeId = 1
        AND Score BETWEEN 50 AND 100
    ) AS QScore50To100,
    (
        SELECT COUNT(*) 
        FROM ComplexPostAnalysis 
        WHERE OwnerUserId = u.UserId
        AND PostTypeId = 2
        AND Score BETWEEN 10 AND 50
    ) AS AScore10To50,
    -- String manipulation
    UPPER(SUBSTRING(u.DisplayName, 1, 1)) || LOWER(SUBSTRING(u.DisplayName, 2)) AS FormattedDisplayName,
    -- Complex predicate based on multiple conditions
    CASE 
        WHEN u.Reputation > 10000 AND u.TotalPosts > 50 AND u.TotalBadges > 5
        THEN 'Elite Contributor'
        WHEN u.Reputation > 5000 AND u.TotalPosts > 20
        THEN 'Active Contributor'
        WHEN u.Reputation > 1000 OR u.TotalPosts > 10
        THEN 'Contributor'
        ELSE 'Member'
    END AS UserRole,
    -- Final calculation with null handling
    (
        u.TotalQuestionScore + u.TotalAnswerScore + 
        (u.GoldBadges * 100) + (u.SilverBadges * 50) + (u.BronzeBadges * 10)
    ) AS CumulativeScore
FROM UserMetrics u
WHERE 
    u.DisplayName IS NOT NULL AND 
    u.TotalPosts > 0 AND
    -- Complex date filtering
    u.LastPostDate >= NOW() - INTERVAL '30 days' AND
    -- Complex numeric filtering
    u.Reputation >= (
        SELECT AVG(Reputation) 
        FROM Users 
        WHERE Id IN (
            SELECT DISTINCT OwnerUserId 
            FROM Posts 
            WHERE CreationDate >= NOW() - INTERVAL '30 days'
        )
    )
-- Complex sorting with multiple criteria
ORDER BY 
    u.TotalQuestionScore DESC,
    u.TotalAnswerScore DESC,
    u.RankByScore ASC,
    u.TotalBadges DESC,
    u.Reputation DESC
-- Limiting results for performance benchmarking
LIMIT 200;