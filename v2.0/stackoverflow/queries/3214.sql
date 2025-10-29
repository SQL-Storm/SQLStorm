-- {"query": "3214.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2309}
WITH UserPosts AS (
    SELECT
        u.Id                AS UserId,
        u.DisplayName,
        p.Id                AS PostId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        p.ViewCount,
        p.FavoriteCount,
        COALESCE(p.Tags,'') AS Tags,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) AS rn
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE u.Reputation > 1000
),
UserBadgeScore AS (
    SELECT
        b.UserId,
        SUM(CASE b.Class WHEN 1 THEN 100 WHEN 2 THEN 50 ELSE 10 END) AS BadgeScore
    FROM Badges b
    GROUP BY b.UserId
),
UserVoteScore AS (
    SELECT
        v.UserId,
        SUM(CASE vt.Id WHEN 2 THEN 5 WHEN 3 THEN -2 ELSE 0 END) AS VoteScore
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '365 days')
    GROUP BY v.UserId
),
TagUsage AS (
    WITH RECURSIVE nums(n) AS (
        SELECT 1
        UNION ALL
        SELECT n+1 FROM nums WHERE n < 50
    ),
    splitted AS (
        SELECT
            up.UserId,
            NULLIF(TRIM(SPLIT_PART(REPLACE(REPLACE(up.Tags,'<',''),'>',''), ' ', n)), '') AS TagName
        FROM UserPosts up
        CROSS JOIN nums
    )
    SELECT
        s.UserId,
        s.TagName AS TagName,
        COUNT(*) AS TagCount
    FROM splitted s
    JOIN Tags t ON t.TagName = s.TagName
    WHERE s.TagName IS NOT NULL
    GROUP BY s.UserId, s.TagName
),
RecentActivity AS (
    SELECT
        up.UserId,
        MAX(up.CreationDate) AS LastActivity
    FROM UserPosts up
    GROUP BY up.UserId
)
SELECT
    u.Id                                   AS UserId,
    u.DisplayName,
    COALESCE(ub.BadgeScore,0)              AS BadgeScore,
    COALESCE(uv.VoteScore,0)               AS VoteScore,
    COALESCE(ra.LastActivity, u.CreationDate) AS RecentActivity,
    COUNT(DISTINCT up.PostId) FILTER (WHERE up.PostTypeId = 1) AS QuestionCount,
    COUNT(DISTINCT up.PostId) FILTER (WHERE up.PostTypeId = 2) AS AnswerCount,
    SUM(COALESCE(up.Score,0))              AS TotalPostScore,
    SUM(COALESCE(up.ViewCount,0))          AS TotalViews,
    SUM(COALESCE(up.FavoriteCount,0))      AS TotalFavorites,
    ROW_NUMBER() OVER (
        ORDER BY (COALESCE(ub.BadgeScore,0)*2
                  + COALESCE(uv.VoteScore,0)
                  + SUM(COALESCE(up.Score,0))) DESC
    )                                      AS ActivityRank
FROM Users u
LEFT JOIN UserPosts up        ON up.UserId = u.Id AND up.rn = 1
LEFT JOIN UserBadgeScore ub   ON ub.UserId = u.Id
LEFT JOIN UserVoteScore uv    ON uv.UserId = u.Id
LEFT JOIN RecentActivity ra   ON ra.UserId = u.Id
WHERE (u.Location IS NOT NULL AND u.Location ILIKE '%USA%')
   OR (u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl ILIKE '%.org')
GROUP BY
    u.Id, u.DisplayName, ub.BadgeScore,
    uv.VoteScore, ra.LastActivity, u.CreationDate
HAVING COUNT(*) > 0

UNION ALL

SELECT
    -1                                            AS UserId,
    'Aggregate'                                   AS DisplayName,
    SUM(ub.BadgeScore)                            AS BadgeScore,
    SUM(uv.VoteScore)                             AS VoteScore,
    MAX(ra.LastActivity)                          AS RecentActivity,
    COUNT(DISTINCT up.PostId) FILTER (WHERE up.PostTypeId = 1) AS QuestionCount,
    COUNT(DISTINCT up.PostId) FILTER (WHERE up.PostTypeId = 2) AS AnswerCount,
    SUM(COALESCE(up.Score,0))                     AS TotalPostScore,
    SUM(COALESCE(up.ViewCount,0))                 AS TotalViews,
    SUM(COALESCE(up.FavoriteCount,0))             AS TotalFavorites,
    NULL                                          AS ActivityRank
FROM UserPosts up
LEFT JOIN UserBadgeScore ub ON ub.UserId = up.UserId
LEFT JOIN UserVoteScore uv  ON uv.UserId = up.UserId
LEFT JOIN RecentActivity ra ON ra.UserId = up.UserId
WHERE up.rn = 1;