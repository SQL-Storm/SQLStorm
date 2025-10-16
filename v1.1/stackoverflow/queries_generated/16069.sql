-- {"query": "16069.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 163450, "output_tokens": 150594} 

WITH UserEngagementMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS NetVotes,
        EXTRACT(YEAR FROM AGE(u.LastAccessDate, u.CreationDate)) AS TenureYears,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY u.Reputation DESC) AS YearlyRepRank,
        DENSE_RANK() OVER (ORDER BY COALESCE(u.Views, 0) DESC) AS ViewRank,
        COUNT(b.Id) OVER (PARTITION BY u.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id) AS GoldBadges
    FROM Users u
    LEFT OUTER JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000 
        AND u.LastAccessDate >= CURRENT_DATE - INTERVAL '2 years'
        AND (u.Location IS NULL OR LENGTH(TRIM(u.Location)) > 0)
),
PostPerformanceAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 1
            WHEN p.PostTypeId = 2 AND EXISTS (
                SELECT 1 FROM Posts parent 
                WHERE parent.Id = p.ParentId AND parent.AcceptedAnswerId = p.Id
            ) THEN 1
            ELSE 0
        END AS HasAcceptedAnswer,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId, p.PostTypeId ORDER BY p.CreationDate ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) AS RollingAvgScore,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevPostScore,
        LEAD(p.ViewCount, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostViews,
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpvoteCount,
        (SELECT STRING_AGG(DISTINCT t.TagName, '|') 
         FROM Tags t 
         WHERE p.Tags LIKE '%<' || t.TagName || '>%' 
         LIMIT 5) AS TopTags
    FROM Posts p
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '5 years'
        AND (p.PostTypeId IN (1, 2))
        AND p.Score IS NOT NULL
),
TagExpertise AS (
    SELECT 
        p.OwnerUserId,
        UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS TagName,
        COUNT(*) AS PostsInTag,
        AVG(p.Score) AS AvgTagScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianTagScore
    FROM Posts p
    WHERE p.PostTypeId = 1 
        AND p.Tags IS NOT NULL 
        AND LENGTH(p.Tags) > 2
    GROUP BY p.OwnerUserId, TagName
    HAVING COUNT(*) >= 5
),
ComplexAggregation AS (
    SELECT 
        uem.Id AS UserId,
        uem.DisplayName,
        uem.Reputation,
        uem.YearlyRepRank,
        uem.TotalBadges,
        uem.GoldBadges,
        COUNT(DISTINCT ppa.PostId) AS TotalPosts,
        SUM(CASE WHEN ppa.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN ppa.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(NULLIF(ppa.Score, 0)) AS AvgNonZeroScore,
        MAX(ppa.ViewCount) AS MaxViews,
        SUM(ppa.HasAcceptedAnswer) AS AcceptedCount,
        COALESCE(AVG(ppa.RollingAvgScore), 0) AS OverallRollingAvg,
        STDDEV_POP(ppa.Score) AS ScoreStdDev,
        (SELECT COUNT(DISTINCT te.TagName) 
         FROM TagExpertise te 
         WHERE te.OwnerUserId = uem.Id AND te.AvgTagScore > 5) AS ExpertTagCount,
        STRING_AGG(DISTINCT SUBSTRING(ppa.TopTags, 1, 50), '; ') AS CombinedTags
    FROM UserEngagementMetrics uem
    LEFT JOIN PostPerformanceAnalysis ppa ON uem.Id = ppa.OwnerUserId
    WHERE uem.YearlyRepRank <= 100
        OR uem.GoldBadges > 0
        OR EXISTS (
            SELECT 1 FROM Votes v
            WHERE v.UserId = uem.Id 
                AND v.VoteTypeId = 8 
                AND v.BountyAmount >= 100
        )
    GROUP BY uem.Id, uem.DisplayName, uem.Reputation, uem.YearlyRepRank, uem.TotalBadges, uem.GoldBadges
    HAVING COUNT(DISTINCT ppa.PostId) > 0
)
SELECT 
    ca.UserId,
    ca.DisplayName,
    ca.Reputation,
    ca.YearlyRepRank,
    ca.TotalBadges,
    ca.GoldBadges,
    ca.TotalPosts,
    ca.QuestionCount,
    ca.AnswerCount,
    ROUND(ca.AvgNonZeroScore::numeric, 2) AS AvgScore,
    ca.MaxViews,
    ca.AcceptedCount,
    ROUND(ca.OverallRollingAvg::numeric, 2) AS RollingAvgScore,
    ROUND(COALESCE(ca.ScoreStdDev, 0)::numeric, 2) AS ScoreVariability,
    ca.ExpertTagCount,
    COALESCE(NULLIF(ca.CombinedTags, ''), 'No Tags') AS TagSummary,
    CASE 
        WHEN ca.Reputation > 50000 AND ca.GoldBadges > 10 THEN 'Elite'
        WHEN ca.Reputation > 25000 OR ca.GoldBadges > 5 THEN 'Advanced'
        WHEN ca.Reputation > 10000 THEN 'Intermediate'
        ELSE 'Developing'
    END AS UserTier,
    ROUND((ca.AcceptedCount::numeric / NULLIF(ca.AnswerCount, 0) * 100), 2) AS AcceptanceRate
FROM ComplexAggregation ca
WHERE ca.TotalPosts >= 10
    AND (ca.AvgNonZeroScore > 1 OR ca.AcceptedCount > 0)
ORDER BY 
    CASE WHEN ca.Reputation > 25000 THEN ca.OverallRollingAvg ELSE ca.Reputation END DESC,
    ca.ExpertTagCount DESC NULLS LAST,
    ca.TotalBadges DESC
LIMIT 500;
