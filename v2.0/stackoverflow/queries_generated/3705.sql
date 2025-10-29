-- {"query": "3705.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1909} 

WITH UserReputation AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(b.Id) FILTER (WHERE b.Class = 1)                     AS GoldBadges,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)                AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2)               AS AvgAnswerScore,
        MAX(p.CreationDate)                                       AS LastPostDate
    FROM Users u
    LEFT JOIN Badges b   ON b.UserId = u.Id
    LEFT JOIN Posts p    ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
UserTagStats AS (
    SELECT
        ut.UserId,
        t.TagName,
        COUNT(*)                                               AS TagUseCount,
        ROW_NUMBER() OVER (PARTITION BY ut.UserId ORDER BY COUNT(*) DESC) AS rn
    FROM (
        SELECT
            p.OwnerUserId AS UserId,
            UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.Tags), '><')) AS Tag
        FROM Posts p
        WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    ) ut
    JOIN Tags t ON t.TagName = ut.Tag
    GROUP BY ut.UserId, t.TagName
),
RecentVotes AS (
    SELECT
        v.UserId,
        COUNT(*) AS RecentVoteCount
    FROM Votes v
    WHERE v.CreationDate >= NOW() - INTERVAL '30 days'
    GROUP BY v.UserId
)
SELECT
    ur.Id,
    ur.DisplayName,
    ur.Reputation,
    ur.GoldBadges,
    ur.AnswerCount,
    ROUND(ur.AvgAnswerScore::numeric, 2)                 AS AvgAnswerScore,
    COALESCE(rv.RecentVoteCount, 0)                      AS RecentVoteCount,
    COALESCE(uts.TagName, '<no tags>')                   AS TopTag,
    COALESCE(uts.TagUseCount, 0)                         AS TopTagUseCount,
    CASE
        WHEN ur.LastPostDate IS NULL THEN 'Never posted'
        ELSE TO_CHAR(ur.LastPostDate, 'YYYY-MM-DD')
    END                                                   AS LastPostDate,
    EXISTS (
        SELECT 1
        FROM Posts q
        WHERE q.OwnerUserId = ur.Id
          AND q.PostTypeId = 1
          AND q.AcceptedAnswerId IS NULL
          AND q.CreationDate < NOW() - INTERVAL '1 year'
    )                                                    AS HasStaleUnanswered
FROM UserReputation ur
LEFT JOIN RecentVotes rv        ON rv.UserId = ur.Id
LEFT JOIN (
    SELECT UserId, TagName, TagUseCount
    FROM UserTagStats
    WHERE rn = 1
) uts                           ON uts.UserId = ur.Id
WHERE (ur.Reputation > 10000 OR ur.GoldBadges > 0)
  AND (ur.AnswerCount IS NOT NULL AND ur.AnswerCount > 0)

UNION ALL

SELECT
    c.UserId,
    u.DisplayName,
    u.Reputation,
    0                         AS GoldBadges,
    0                         AS AnswerCount,
    NULL                      AS AvgAnswerScore,
    0                         AS RecentVoteCount,
    NULL                      AS TopTag,
    0                         AS TopTagUseCount,
    NULL                      AS LastPostDate,
    FALSE                     AS HasStaleUnanswered
FROM Comments c
JOIN Users u ON u.Id = c.UserId
WHERE c.CreationDate >= NOW() - INTERVAL '7 days'
  AND NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)

ORDER BY Reputation DESC NULLS LAST
LIMIT 100;
