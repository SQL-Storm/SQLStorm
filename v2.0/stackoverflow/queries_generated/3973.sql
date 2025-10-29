-- {"query": "3973.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1586} 

WITH UserStats AS (
    SELECT
        u.Id,
        COALESCE(u.DisplayName, 'Anonymous')          AS DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes, 0)                        AS UpVotes,
        COALESCE(u.DownVotes, 0)                      AS DownVotes,
        (COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0)) AS VoteScore,
        COUNT(b.Id) FILTER (WHERE b.Class = 1)       AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2)       AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3)       AS BronzeBadges,
        (SELECT MAX(p.CreationDate)
         FROM Posts p
         WHERE p.OwnerUserId = u.Id)                AS LastPostDate
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
),

TagMetrics AS (
    SELECT
        t.TagName,
        t.Count                                   AS TagUseCount,
        COALESCE(LENGTH(p.Body), 0)               AS ExcerptLength
    FROM Tags t
    LEFT JOIN Posts p ON p.Id = t.ExcerptPostId
),

RecentActivity AS (
    SELECT
        v.UserId,
        MAX(v.CreationDate)                       AS LastVoteDate
    FROM Votes v
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY v.UserId
),

RecentTags AS (
    SELECT DISTINCT
        unnest(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><')) AS TagName,
        p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1                     -- only questions
      AND p.CreationDate > CURRENT_DATE - INTERVAL '7 days'
)

SELECT
    us.Id,
    us.DisplayName,
    us.Reputation,
    us.VoteScore,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    COALESCE(ra.LastVoteDate, us.LastPostDate) AS RecentActivityDate,
    ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.VoteScore DESC) AS ReputationRank,
    tm.TagName,
    tm.TagUseCount,
    CASE
        WHEN tm.ExcerptLength > 1000 THEN 'Long'
        WHEN tm.ExcerptLength = 0      THEN 'Missing'
        ELSE 'Short'
    END AS ExcerptSize
FROM UserStats us
LEFT JOIN RecentActivity ra       ON ra.UserId = us.Id
LEFT JOIN RecentTags rt           ON rt.OwnerUserId = us.Id
LEFT JOIN TagMetrics tm           ON tm.TagName = rt.TagName
WHERE us.Reputation > 1000
  AND (us.GoldBadges > 0 OR us.SilverBadges > 0)

UNION ALL

SELECT
    -1                               AS Id,
    'DeletedUser'                    AS DisplayName,
    0                                AS Reputation,
    0                                AS VoteScore,
    0                                AS GoldBadges,
    0                                AS SilverBadges,
    0                                AS BronzeBadges,
    NULL                             AS RecentActivityDate,
    NULL                             AS ReputationRank,
    NULL                             AS TagName,
    NULL                             AS TagUseCount,
    NULL                             AS ExcerptSize
WHERE NOT EXISTS (SELECT 1 FROM Users WHERE Reputation > 0)

ORDER BY ReputationRank NULLS LAST
LIMIT 100;
