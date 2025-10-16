-- {"query": "17032.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 77055, "output_tokens": 75450} 

WITH UserMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.Location, 'Unknown') AS Location,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS AvgPostScore,
        SUM(COALESCE(p.Score, 0)) AS TotalScore,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) OVER (PARTITION BY u.Id) AS MedianScore
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
),
TagExpertise AS (
    SELECT 
        p.OwnerUserId,
        SUBSTRING(UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) FROM 1 FOR 30) AS Tag,
        COUNT(*) AS TagPostCount,
        SUM(p.Score) AS TagScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY SUM(p.Score) DESC NULLS LAST) AS TagRank
    FROM Posts p
    WHERE p.Tags IS NOT NULL 
        AND p.PostTypeId = 1
        AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, Tag
),
BadgePatterns AS (
    SELECT 
        b.UserId,
        STRING_AGG(DISTINCT 
            CASE b.Class 
                WHEN 1 THEN '🥇' || b.Name 
                WHEN 2 THEN '🥈' || b.Name 
                WHEN 3 THEN '🥉' || b.Name 
            END, ', ' ORDER BY b.Class, b.Name
        ) AS BadgeCollection,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldCount,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverCount,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeCount,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
EngagementScore AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT c.UserId) AS UniqueCommenters,
        AVG(EXTRACT(EPOCH FROM (c.CreationDate - p.CreationDate))/3600.0) AS AvgHoursToFirstComment,
        COALESCE(
            SUM(CASE 
                WHEN v.VoteTypeId = 2 THEN 1 
                WHEN v.VoteTypeId = 3 THEN -1 
                ELSE 0 
            END), 0
        ) AS NetVotes,
        COUNT(DISTINCT pl.RelatedPostId) FILTER (WHERE pl.LinkTypeId = 1) AS LinkedPostCount
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
)
SELECT 
    um.DisplayName,
    um.Reputation,
    um.Location,
    COALESCE(um.PostCount, 0) AS TotalPosts,
    ROUND(um.AvgPostScore::NUMERIC, 2) AS AvgScore,
    um.ReputationRank,
    CASE 
        WHEN um.Reputation > 100000 THEN 'Legendary'
        WHEN um.Reputation > 50000 THEN 'Epic'
        WHEN um.Reputation > 10000 THEN 'Trusted'
        WHEN um.Reputation > 1000 THEN 'Established'
        ELSE 'Rising'
    END AS UserTier,
    COALESCE(te.Tag, 'No specialty') AS TopTag,
    COALESCE(te.TagScore, 0) AS TopTagScore,
    COALESCE(bp.BadgeCollection, 'No badges') AS Badges,
    COALESCE(bp.GoldCount, 0) + COALESCE(bp.SilverCount, 0) * 0.5 + COALESCE(bp.BronzeCount, 0) * 0.25 AS BadgeScore,
    COALESCE(es.UniqueCommenters, 0) AS CommunityReach,
    ROUND(COALESCE(es.AvgHoursToFirstComment, 0)::NUMERIC, 1) AS ResponseTime,
    (
        SELECT COUNT(DISTINCT ph.PostId)
        FROM PostHistory ph
        WHERE ph.UserId = um.Id
            AND ph.PostHistoryTypeId IN (4, 5, 6)
            AND EXISTS (
                SELECT 1 
                FROM Posts p2 
                WHERE p2.Id = ph.PostId 
                    AND p2.OwnerUserId != um.Id
            )
    ) AS EditContributions,
    CASE 
        WHEN um.QuestionCount > 0 AND um.AnswerCount > 0 
        THEN ROUND((um.AnswerCount::NUMERIC / NULLIF(um.QuestionCount, 0)), 2)
        ELSE NULL 
    END AS AnswerQuestionRatio,
    COALESCE(
        (
            SELECT STRING_AGG(p3.Title, ' | ' ORDER BY p3.Score DESC)
            FROM (
                SELECT p2.Title, p2.Score
                FROM Posts p2
                WHERE p2.OwnerUserId = um.Id
                    AND p2.Title IS NOT NULL
                    AND p2.Score > 10
                    AND LENGTH(p2.Title) > 20
                ORDER BY p2.Score DESC
                LIMIT 3
            ) p3
        ), 
        'No popular posts'
    ) AS TopPosts,
    CASE 
        WHEN bp.LastBadgeDate > CURRENT_DATE - INTERVAL '30 days' THEN '🔥 Active'
        WHEN bp.LastBadgeDate > CURRENT_DATE - INTERVAL '90 days' THEN '📊 Regular'
        ELSE '💤 Inactive'
    END AS ActivityStatus,
    LOG(GREATEST(um.Reputation, 1)) * 
    COALESCE(SQRT(um.PostCount), 1) * 
    (1 + COALESCE(es.NetVotes, 0) / 100.0) AS InfluenceScore
FROM UserMetrics um
LEFT OUTER JOIN TagExpertise te ON um.Id = te.OwnerUserId AND te.TagRank = 1
LEFT OUTER JOIN BadgePatterns bp ON um.Id = bp.UserId
LEFT OUTER JOIN EngagementScore es ON um.Id = es.OwnerUserId
WHERE um.PostCount > 5
    AND (um.Reputation > 1000 OR bp.GoldCount > 0)
    AND um.DisplayName IS NOT NULL
    AND NOT EXISTS (
        SELECT 1
        FROM PostHistory ph2
        WHERE ph2.UserId = um.Id
            AND ph2.PostHistoryTypeId = 12
            AND ph2.CreationDate > CURRENT_DATE - INTERVAL '6 months'
    )
ORDER BY 
    InfluenceScore DESC NULLS LAST,
    um.Reputation DESC,
    um.PostCount DESC
LIMIT 100;
