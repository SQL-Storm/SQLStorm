-- {"query": "9043.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 2232} 

WITH
-- 1. Recent activity per user: posts in last 30d and total bounty started/closed
RecentActivity AS (
    SELECT
        u.Id           AS UserId,
        u.DisplayName,
        COALESCE(
            COUNT(p.Id) FILTER (WHERE p.CreationDate >= now() - INTERVAL '30 days'),
            0
        )             AS PostsLast30,
        COALESCE(
            SUM(v.BountyAmount) FILTER (WHERE v.VoteTypeId IN (8,9)),
            0
        )             AS TotalBounty
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.UserId      = u.Id
    GROUP BY u.Id, u.DisplayName
),
-- 2. Tag usage frequency on questions, with window ranking
TagFrequency AS (
    SELECT
        t.TagName,
        COUNT(*)                AS UsageCount,
        ROW_NUMBER() OVER (
            ORDER BY COUNT(*) DESC
        )                       AS TagRank
    FROM Posts p
    CROSS JOIN LATERAL UNNEST(
        string_to_array(
            substring(p.Tags, 2, length(p.Tags) - 2),
            '><'
        )
    ) AS t(TagName)
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
),
-- 3. Top‑10 tags joined back to recent activity
HighActivity AS (
    SELECT
        ra.*,
        tf.UsageCount,
        tf.TagRank
    FROM RecentActivity ra
    LEFT JOIN TagFrequency tf
      ON tf.TagRank <= 10
),
-- 4. Count of duplicate links per post
DupCountPerPost AS (
    SELECT
        pl.PostId,
        COUNT(*) AS DupCount
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3
    GROUP BY pl.PostId
),
-- 5. Correlated subquery example: high‑score answers per user
HighScoreAnswers AS (
    SELECT
        u.Id                     AS UserId,
        (
            SELECT COUNT(*)
            FROM Posts p2
            WHERE
                p2.OwnerUserId = u.Id
                AND p2.PostTypeId = 2
                AND p2.Score > COALESCE(ra.TotalBounty,0) / NULLIF(NULLIF(ra.PostsLast30,0),0)
        )                       AS HighScoreAnswerCount
    FROM Users u
    LEFT JOIN RecentActivity ra ON ra.UserId = u.Id
),
-- 6. Combine HighActivity with duplicate‑link summary via a FULL OUTER JOIN
ActivityWithDups AS (
    SELECT
        ha.UserId,
        ha.DisplayName,
        ha.PostsLast30,
        ha.TotalBounty,
        ha.UsageCount      AS TopTagUses,
        ha.TagRank         AS TopTagRank,
        dc.DupCount        AS PostDuplicates,
        hs.HighScoreAnswerCount
    FROM HighActivity ha
    FULL OUTER JOIN DupCountPerPost dc
      ON dc.PostId = ha.UserId   -- intentionally mismatched join to exercise NULL logic
    LEFT JOIN HighScoreAnswers hs
      ON hs.UserId = ha.UserId
)
-- Final SELECT with window functions, string operations, NULL logic, set operator
SELECT
    awd.UserId,
    awd.DisplayName,
    LENGTH(COALESCE(awd.DisplayName,''))       AS NameLength,
    CONCAT(awd.DisplayName,'_',awd.UserId)     AS UserKey,
    awd.PostsLast30,
    awd.TotalBounty,
    awd.TopTagUses,
    awd.TopTagRank,
    awd.PostDuplicates,
    awd.HighScoreAnswerCount,
    NULLIF(awd.DisplayName,'')                 AS CleanDisplayName,
    LAG(awd.PostDuplicates) OVER (
        ORDER BY awd.TotalBounty DESC NULLS LAST
    )                                           AS PrevUserDupCount
FROM ActivityWithDups awd
WHERE
    (
        awd.PostsLast30 > 5
        AND awd.PostDuplicates IS NULL
    )
    OR
    (
        awd.TotalBounty > 100
        AND awd.PostDuplicates > 2
    )
EXCEPT
-- Exclude any “dummy” rows for users without activity
SELECT
    u.Id,
    u.DisplayName,
    0,0,0,0,0,0,0,NULL
FROM Users u;
