-- {"query": "3885.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1782}
WITH UserStats AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
BadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(*) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        STRING_AGG(DISTINCT b.Name, ', ') AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId
),
TopTagPerUser AS (
    SELECT 
        b.UserId,
        t.TagName,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY COUNT(*) DESC) AS rn
    FROM Badges b
    JOIN Tags t ON b.TagBased = TRUE AND t.TagName = b.Name
    GROUP BY b.UserId, t.TagName
),
RecentVotes AS (
    SELECT 
        v.UserId,
        COUNT(CASE WHEN v.CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY) THEN 1 END) AS RecentVoteCount
    FROM Votes v
    GROUP BY v.UserId
)
SELECT 
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.QuestionCount,
    us.AnswerCount,
    us.TotalScore,
    COALESCE(bs.BadgeCount, 0) AS BadgeCount,
    COALESCE(bs.GoldBadges, 0) AS GoldBadges,
    COALESCE(bs.SilverBadges, 0) AS SilverBadges,
    COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(bs.BadgeNames, '') AS BadgeNames,
    tt.TagName AS TopTag,
    COALESCE(rv.RecentVoteCount, 0) AS RecentVoteCount,
    CASE 
        WHEN us.Reputation > 20000 THEN 'Power User'
        WHEN COALESCE(bs.BadgeCount, 0) >= 10 AND us.TotalScore > 5000 THEN 'Veteran'
        ELSE 'Regular'
    END AS UserTier,
    -- Format date in a dialect-neutral way: cast to DATE (string format may be handled by client)
    CASE WHEN us.LastPostDate IS NULL THEN NULL ELSE CAST(us.LastPostDate AS DATE) END AS LastPostDate
FROM UserStats us
LEFT JOIN BadgeStats bs       ON bs.UserId = us.Id
LEFT JOIN (
    SELECT UserId, TagName FROM TopTagPerUser WHERE rn = 1
) tt                         ON tt.UserId = us.Id
LEFT JOIN RecentVotes rv     ON rv.UserId = us.Id
WHERE (us.Reputation > 10000 OR COALESCE(bs.BadgeCount, 0) >= 5)

UNION ALL

SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    0 AS QuestionCount,
    0 AS AnswerCount,
    0 AS TotalScore,
    0 AS BadgeCount,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    '' AS BadgeNames,
    NULL AS TopTag,
    0 AS RecentVoteCount,
    'Newbie' AS UserTier,
    NULL AS LastPostDate
FROM Users u
WHERE u.Reputation < 100
  AND NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)

ORDER BY Reputation DESC, BadgeCount DESC
LIMIT 100;