-- {"query": "3433.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1878}
WITH RecentAnswers AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ParentId,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVoteCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVoteCount
    FROM Posts p
    WHERE p.PostTypeId = 2
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
),
UserMetrics AS (
    SELECT 
        u.Id                                         AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(a.Id) FILTER (WHERE a.Score > 0)       AS PositiveAnswerCount,
        COUNT(a.Id) FILTER (WHERE a.Score <= 0)      AS NonPositiveAnswerCount,
        CAST(AVG(a.Score) AS numeric(10,2))          AS AvgAnswerScore,
        SUM(CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) AS AcceptedAnswerCount,
        MAX(a.CreationDate)                          AS LastAnswerDate,
        STRING_AGG(DISTINCT t.TagName, ', ')         AS TagsAnswered
    FROM Users u
    LEFT JOIN RecentAnswers a       ON a.OwnerUserId = u.Id
    LEFT JOIN Posts q               ON q.Id = a.ParentId
    LEFT JOIN LATERAL (
        SELECT unnest(string_to_array(q.Tags, '><')) AS rawTag
    ) AS splitTags ON TRUE
    LEFT JOIN Tags t                ON t.TagName = trim(both '<>' FROM splitTags.rawTag)
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
BadgeRanks AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadgeCount,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadgeCount,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadgeCount,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS RecentBadgeRank,
        b.Date
    FROM Badges b
    GROUP BY b.UserId, b.Date
)
SELECT 
    um.UserId,
    um.DisplayName,
    um.Reputation,
    um.PositiveAnswerCount,
    um.NonPositiveAnswerCount,
    um.AvgAnswerScore,
    um.AcceptedAnswerCount,
    um.LastAnswerDate,
    um.TagsAnswered,
    COALESCE(br.GoldBadgeCount,   0) AS GoldBadges,
    COALESCE(br.SilverBadgeCount, 0) AS SilverBadges,
    COALESCE(br.BronzeBadgeCount, 0) AS BronzeBadges,
    CASE 
        WHEN um.Reputation > 20000 THEN 'Legendary'
        WHEN um.Reputation > 10000 THEN 'Elite'
        WHEN um.Reputation > 5000  THEN 'Pro'
        ELSE 'Rookie'
    END                                         AS ReputationTier,
    ROW_NUMBER() OVER (ORDER BY um.Reputation DESC, um.AvgAnswerScore DESC) AS ReputationRank
FROM UserMetrics um
LEFT JOIN BadgeRanks br 
       ON br.UserId = um.UserId 
      AND br.RecentBadgeRank = 1
WHERE um.PositiveAnswerCount > 0

UNION ALL

SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    0                AS PositiveAnswerCount,
    0                AS NonPositiveAnswerCount,
    NULL             AS AvgAnswerScore,
    0                AS AcceptedAnswerCount,
    NULL             AS LastAnswerDate,
    NULL             AS TagsAnswered,
    0                AS GoldBadges,
    0                AS SilverBadges,
    0                AS BronzeBadges,
    'NoAnswers'      AS ReputationTier,
    NULL             AS ReputationRank
FROM Users u
WHERE NOT EXISTS (
    SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2
)
ORDER BY ReputationRank NULLS LAST, Reputation DESC
LIMIT 100;