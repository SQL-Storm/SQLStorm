-- {"query": "16068.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 161115, "output_tokens": 148533} 

WITH RECURSIVE UserEngagementMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS NetVotes,
        EXTRACT(YEAR FROM u.CreationDate) AS JoinYear,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 1000 THEN 'Advanced'
            WHEN u.Reputation > 100 THEN 'Intermediate'
            ELSE 'Beginner'
        END AS UserTier
    FROM Users u
    WHERE u.Reputation > 0 AND u.CreationDate >= '2015-01-01'
),
PostPerformance AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        COALESCE(LENGTH(p.Body), 0) AS BodyLength,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRank,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgUserScore,
        PERCENT_RANK() OVER (ORDER BY p.Score) AS ScorePercentile,
        LAG(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevPostDate,
        LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostScore
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) 
        AND p.CreationDate >= '2018-01-01'
        AND p.OwnerUserId IS NOT NULL
),
TagEngagement AS (
    SELECT 
        UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS TagName,
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        COUNT(*) OVER (PARTITION BY UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'))) AS TagPopularity
    FROM Posts p
    WHERE p.Tags IS NOT NULL 
        AND p.PostTypeId = 1
        AND p.CreationDate >= '2019-01-01'
),
BadgeInfluence AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldCount,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverCount,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeCount,
        STRING_AGG(DISTINCT b.Name, ', ') FILTER (WHERE b.Class = 1) AS GoldBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    WHERE b.Date >= '2017-01-01'
    GROUP BY b.UserId
    HAVING COUNT(*) >= 5
),
ComplexMetrics AS (
    SELECT 
        uem.Id AS UserId,
        uem.DisplayName,
        uem.UserTier,
        COALESCE(pp.AvgUserScore, 0) AS AvgScore,
        COALESCE(bi.GoldCount, 0) + COALESCE(bi.SilverCount, 0) * 0.5 + COALESCE(bi.BronzeCount, 0) * 0.25 AS WeightedBadgeScore,
        (SELECT COUNT(DISTINCT v.Id) 
         FROM Votes v 
         JOIN Posts p2 ON v.PostId = p2.Id
         WHERE p2.OwnerUserId = uem.Id 
             AND v.VoteTypeId = 2
             AND v.CreationDate >= uem.CreationDate + INTERVAL '30 days') AS UpvotesReceived,
        (SELECT AVG(c.Score)
         FROM Comments c
         JOIN Posts p3 ON c.PostId = p3.Id
         WHERE c.UserId = uem.Id
             AND c.Score IS NOT NULL) AS AvgCommentScore,
        CASE 
            WHEN EXISTS (
                SELECT 1 FROM Posts p4 
                WHERE p4.OwnerUserId = uem.Id 
                    AND p4.AcceptedAnswerId IS NOT NULL
            ) THEN 1 
            ELSE 0 
        END AS HasAcceptedAnswer
    FROM UserEngagementMetrics uem
    LEFT JOIN PostPerformance pp ON uem.Id = pp.OwnerUserId AND pp.PostRank = 1
    LEFT JOIN BadgeInfluence bi ON uem.Id = bi.UserId
)
SELECT 
    cm.DisplayName,
    cm.UserTier,
    ROUND(cm.AvgScore::numeric, 2) AS AvgPostScore,
    cm.WeightedBadgeScore,
    cm.UpvotesReceived,
    COALESCE(ROUND(cm.AvgCommentScore::numeric, 2), 0) AS AvgCommentScore,
    te.TopTags,
    te.TagDiversity,
    ph.EditCount,
    pl.LinkCount,
    CASE 
        WHEN cm.WeightedBadgeScore > 50 AND cm.AvgScore > 10 THEN 'Influencer'
        WHEN cm.UpvotesReceived > 100 THEN 'Popular'
        WHEN ph.EditCount > 20 THEN 'Contributor'
        ELSE 'Regular'
    END AS UserCategory,
    COALESCE(NULLIF(ROUND((cm.UpvotesReceived::numeric / NULLIF(ph.EditCount, 0)), 2), 0), 0) AS EngagementRatio
FROM ComplexMetrics cm
LEFT JOIN LATERAL (
    SELECT 
        STRING_AGG(te.TagName, ', ' ORDER BY te.TagPopularity DESC) AS TopTags,
        COUNT(DISTINCT te.TagName) AS TagDiversity
    FROM TagEngagement te
    WHERE te.OwnerUserId = cm.UserId
    GROUP BY te.OwnerUserId
    LIMIT 1
) te ON true
LEFT JOIN LATERAL (
    SELECT COUNT(*) AS EditCount
    FROM PostHistory ph
    WHERE ph.UserId = cm.UserId
        AND ph.PostHistoryTypeId IN (4, 5, 6)
) ph ON true
LEFT JOIN LATERAL (
    SELECT COUNT(DISTINCT pl.Id) AS LinkCount
    FROM PostLinks pl
    JOIN Posts p ON pl.PostId = p.Id
    WHERE p.OwnerUserId = cm.UserId
) pl ON true
WHERE cm.AvgScore IS NOT NULL
    AND (cm.WeightedBadgeScore > 0 OR cm.UpvotesReceived > 10)
    AND NOT (cm.AvgCommentScore IS NULL AND ph.EditCount = 0)
ORDER BY 
    CASE cm.UserTier
        WHEN 'Elite' THEN 1
        WHEN 'Advanced' THEN 2
        WHEN 'Intermediate' THEN 3
        ELSE 4
    END,
    cm.WeightedBadgeScore DESC,
    cm.UpvotesReceived DESC
LIMIT 500;
