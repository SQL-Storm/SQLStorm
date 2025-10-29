-- {"query": "7026.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1913} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Elite'
            WHEN u.Reputation >= 1000 THEN 'Advanced'
            WHEN u.Reputation >= 100 THEN 'Beginner'
            ELSE 'Newbie'
        END AS ReputationLevel,
        -- Calculate user's activity score based on posts, comments, and reputation
        (COUNT(DISTINCT p.Id) * 10 + 
         COUNT(DISTINCT c.Id) * 5 + 
         u.Reputation / 100) AS ActivityScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.AccountId IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostCount,
        ActivityScore,
        RANK() OVER (ORDER BY ActivityScore DESC) AS RankByActivity,
        DENSE_RANK() OVER (ORDER BY Reputation DESC) AS RankByReputation
    FROM UserStats
    WHERE PostCount > 0
),
PostAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN p.PostTypeId = 1 AND p.AnswerCount = 0 THEN 'Unanswered'
            ELSE 'Other'
        END AS QuestionStatus,
        -- Calculate engagement ratio (comments + answers) / views
        CASE 
            WHEN p.ViewCount > 0 THEN 
                (CAST(p.CommentCount + COALESCE(p.AnswerCount, 0) AS FLOAT) / CAST(p.ViewCount AS FLOAT)) * 100
            ELSE 0
        END AS EngagementRatio,
        -- Extract top tag if available
        CASE 
            WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 4 THEN 
                SUBSTRING(p.Tags, 2, POSITION('>' IN SUBSTRING(p.Tags, 2)) - 1)
            ELSE NULL
        END AS TopTag,
        -- Calculate post age in days from creation to now
        EXTRACT(DAY FROM (CURRENT_TIMESTAMP - p.CreationDate)) AS PostAgeDays
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Only questions and answers
),
UserPostActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT pa.PostId) AS TotalPosts,
        SUM(CASE WHEN pa.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN pa.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(pa.Score) AS AvgScore,
        SUM(pa.ViewCount) AS TotalViews,
        AVG(pa.EngagementRatio) AS AvgEngagementRatio,
        MAX(pa.PostAgeDays) AS MaxPostAge
    FROM Users u
    INNER JOIN PostAnalysis pa ON u.Id = pa.OwnerUserId
    WHERE pa.PostAgeDays <= 365 -- Posts created within the last year
    GROUP BY u.Id, u.DisplayName
),
ComplexFilters AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT p2.Id) AS RecentPosts,
        SUM(CASE WHEN p.Score > 10 THEN 1 ELSE 0 END) AS HighScorePosts,
        COUNT(DISTINCT CASE WHEN p.Tags LIKE '%<c>%<%' THEN p.Id END) AS CTaggedPosts,
        MAX(p.CreationDate) AS LatestPostDate,
        'ComplexUser' AS UserType,
        -- Calculate a composite score involving multiple factors
        (COUNT(DISTINCT p.Id) * 2 +
         SUM(CASE WHEN p.Score > 10 THEN 1 ELSE 0 END) * 5 +
         COUNT(DISTINCT CASE WHEN p.Tags LIKE '%<c>%<%' THEN p.Id END) * 3 +
         COALESCE(SUM(p.ViewCount) / NULLIF(COUNT(DISTINCT p.Id), 0), 0) / 1000) AS CompositeScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Posts p2 ON u.Id = p2.OwnerUserId 
        AND p2.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '30 days'
    WHERE u.Reputation >= 100
        AND u.AccountId IS NOT NULL
        AND (p.CreationDate IS NULL OR p.CreationDate <= CURRENT_TIMESTAMP)
    GROUP BY u.Id, u.DisplayName
),
AggregatedData AS (
    SELECT 
        u.UserId,
        u.DisplayName,
        u.Reputation,
        u.PostCount,
        u.ActivityScore,
        u.RankByActivity,
        u.RankByReputation,
        pa.TotalPosts,
        pa.QuestionCount,
        pa.AnswerCount,
        pa.AvgScore,
        pa.TotalViews,
        pa.AvgEngagementRatio,
        pa.MaxPostAge,
        cf.TotalPosts AS FilteredTotalPosts,
        cf.RecentPosts,
        cf.HighScorePosts,
        cf.CTaggedPosts,
        cf.LatestPostDate,
        cf.UserType,
        cf.CompositeScore,
        -- Calculate normalized composite score
        (cf.CompositeScore - MIN(cf.CompositeScore) OVER()) / 
        (MAX(cf.CompositeScore) OVER() - MIN(cf.CompositeScore) OVER()) * 100 AS NormalizedScore
    FROM TopUsers u
    INNER JOIN UserPostActivity pa ON u.UserId = pa.UserId
    INNER JOIN ComplexFilters cf ON u.UserId = cf.UserId
)
SELECT 
    ad.UserId,
    ad.DisplayName,
    ad.Reputation,
    ad.PostCount,
    ad.ActivityScore,
    ad.RankByActivity,
    ad.RankByReputation,
    ad.TotalPosts,
    ad.QuestionCount,
    ad.AnswerCount,
    ad.AvgScore,
    ad.TotalViews,
    ad.AvgEngagementRatio,
    ad.MaxPostAge,
    ad.FilteredTotalPosts,
    ad.RecentPosts,
    ad.HighScorePosts,
    ad.CTaggedPosts,
    ad.LatestPostDate,
    ad.UserType,
    ad.CompositeScore,
    ad.NormalizedScore,
    -- Calculate performance metrics
    CASE 
        WHEN ad.MaxPostAge <= 30 AND ad.CompositeScore > 100 THEN 'High Performance'
        WHEN ad.MaxPostAge <= 90 AND ad.CompositeScore > 50 THEN 'Medium Performance'
        WHEN ad.MaxPostAge > 90 THEN 'Low Performance'
        ELSE 'Variable Performance'
    END AS PerformanceCategory,
    -- Generate ranking description
    CASE 
        WHEN ad.RankByActivity <= 5 THEN 'Top Tier Activity'
        WHEN ad.RankByActivity <= 15 THEN 'High Activity'
        WHEN ad.RankByActivity <= 30 THEN 'Moderate Activity'
        ELSE 'Lower Activity'
    END AS ActivityDescription,
    -- Include user status
    CASE 
        WHEN ad.Reputation >= 100000 THEN 'Legendary'
        WHEN ad.Reputation >= 10000 THEN 'Elite'
        WHEN ad.Reputation >= 1000 THEN 'Advanced'
        WHEN ad.Reputation >= 100 THEN 'Beginner'
        ELSE 'Newbie'
    END AS UserStatus,
    -- Calculate efficiency score
    CASE 
        WHEN ad.AvgScore > 0 THEN 
            (ad.AvgScore + ad.AvgEngagementRatio) / NULLIF(ad.TotalViews, 0) * 1000
        ELSE 0
    END AS EfficiencyScore
FROM AggregatedData ad
WHERE ad.PostCount > 0 
    AND ad.TotalPosts > 0
    AND ad.CompositeScore IS NOT NULL
    AND EXISTS (
        SELECT 1 FROM Posts p 
        WHERE p.OwnerUserId = ad.UserId 
            AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '1 year'
    )
ORDER BY ad.NormalizedScore DESC, ad.CompositeScore DESC, ad.Reputation DESC
LIMIT 1000;