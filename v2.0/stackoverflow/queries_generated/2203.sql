-- {"query": "2203.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1466} 

WITH RankedPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        u.DisplayName AS OwnerName,
        u.Reputation,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn,
        COUNT(*) OVER (PARTITION BY p.PostTypeId) AS total_posts,
        -- Extract tag count via counting '><' in tags + 1 for non-null tags; else 0
        CASE 
            WHEN p.Tags IS NOT NULL THEN
                LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '><', '')) + 1
            ELSE 0 
        END AS TagCount
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2)
),
HighImpactUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COALESCE(SUM(v.Amount), 0) AS TotalBountyReceived
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN (
        SELECT p.OwnerUserId AS UserId, SUM(v.BountyAmount) AS Amount
        FROM Posts p
        JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 8 -- BountyStart
        GROUP BY p.OwnerUserId
    ) v ON v.UserId = u.Id
    WHERE u.Reputation > 5000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostLinksAggregates AS (
    SELECT
        pl.PostId,
        SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedCount,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateCount,
        MAX(pl.CreationDate) AS LastLinkDate
    FROM PostLinks pl
    GROUP BY pl.PostId
),
UserRecentActivity AS (
    SELECT
        u.Id AS UserId,
        MAX(ph.CreationDate) AS LastEditDate,
        COUNT(ph.Id) AS TotalEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 END) AS CloseVotesCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 END) AS ReopenVotesCount
    FROM Users u
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    GROUP BY u.Id
),
CorrelatedAnswers AS (
    SELECT DISTINCT p.ParentId AS QuestionId
    FROM Posts p
    WHERE p.PostTypeId = 2 AND p.Score > (
        SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.PostTypeId = 2 AND p2.ParentId = p.ParentId
    )
)
SELECT
    rp.Id AS PostId,
    rp.PostTypeId,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.OwnerName,
    rp.Reputation AS OwnerReputation,
    rp.TagCount,
    hl.LinkedCount,
    hl.DuplicateCount,
    hl.LastLinkDate,
    ua.LastEditDate,
    ua.TotalEdits,
    ua.CloseVotesCount,
    ua.ReopenVotesCount,
    hu.GoldBadges,
    hu.SilverBadges,
    hu.BronzeBadges,
    hu.TotalBountyReceived,
    -- Complicated expression: weighted score metric with null logic and string concatenation
    CASE
        WHEN rp.ViewCount > 0 THEN
            ROUND((rp.Score * 1.5 + hu.GoldBadges * 3 + hu.SilverBadges * 2 + hu.BronzeBadges) 
                / NULLIF(rp.ViewCount, 0), 4)
        ELSE NULL
    END AS WeightedScorePerView,
    -- String expression integrating title length and tags presence
    CONCAT(
        'TitleLen:', LENGTH(COALESCE(rp.Title, '')), 
        '; Tags:', CASE WHEN rp.TagCount > 0 THEN CAST(rp.TagCount AS VARCHAR) ELSE 'None' END,
        '; Owner:', COALESCE(rp.OwnerName, 'Anonymous')
    ) AS PostSummary,
    -- Flag if question has at least one high-scoring answer
    CASE WHEN rp.PostTypeId = 1 AND rp.Id IN (SELECT QuestionId FROM CorrelatedAnswers) THEN 1 ELSE 0 END AS HasHighScoreAnswer
FROM RankedPosts rp
LEFT JOIN PostLinksAggregates hl ON rp.Id = hl.PostId
LEFT JOIN Users u ON rp.OwnerName = u.DisplayName -- may join multiple users with same name, okay for benchmark
LEFT JOIN UserRecentActivity ua ON ua.UserId = u.Id
LEFT JOIN HighImpactUsers hu ON hu.Id = u.Id
WHERE rp.rn <= 100
ORDER BY rp.PostTypeId, WeightedScorePerView DESC NULLS LAST, rp.ViewCount DESC
LIMIT 200
UNION
-- Combine with a set operator: get top 50 recent questions with tags containing 'sql'
SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    u.DisplayName AS OwnerName,
    u.Reputation AS OwnerReputation,
    CASE 
        WHEN p.Tags IS NOT NULL THEN
            LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '><', '')) + 1
        ELSE 0 
    END AS TagCount,
    0 AS LinkedCount,
    0 AS DuplicateCount,
    NULL::timestamp AS LastLinkDate,
    NULL::timestamp AS LastEditDate,
    0 AS TotalEdits,
    0 AS CloseVotesCount,
    0 AS ReopenVotesCount,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    0 AS TotalBountyReceived,
    NULL::numeric AS WeightedScorePerView,
    CONCAT(
        'TitleLen:', LENGTH(COALESCE(p.Title, '')), 
        '; Tags:', 'SQL Only',
        '; Owner:', COALESCE(u.DisplayName, 'Anonymous')
    ) AS PostSummary,
    0 AS HasHighScoreAnswer
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId = 1
  AND p.Tags ILIKE '%<sql>%'
ORDER BY p.CreationDate DESC
LIMIT 50;
