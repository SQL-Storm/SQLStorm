-- {"query": "3564.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2417} 

WITH
    q_posts AS (
        SELECT
            p.Id                 AS PostId,
            p.OwnerUserId        AS UserId,
            p.PostTypeId,
            p.Score,
            p.CreationDate,
            p.Tags,
            p.Title,
            p.ViewCount,
            p.FavoriteCount,
            COALESCE(p.AcceptedAnswerId, 0) AS AcceptedAnswerId,
            p.ParentId
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
    ),
    tag_explode AS (
        SELECT
            up.UserId,
            UNNEST( STRING_TO_ARRAY( SUBSTRING(up.Tags, 2, LENGTH(up.Tags)-2), '><' ) ) AS Tag
        FROM q_posts up
        WHERE up.Tags IS NOT NULL
    ),
    tag_counts AS (
        SELECT
            UserId,
            Tag,
            COUNT(*) AS TagUseCount
        FROM tag_explode
        GROUP BY UserId, Tag
    ),
    top_tags AS (
        SELECT
            UserId,
            Tag,
            TagUseCount,
            ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagUseCount DESC, Tag) AS rn
        FROM tag_counts
    ),
    user_badges AS (
        SELECT
            b.UserId,
            COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
            COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
            COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
            COUNT(*)                         AS TotalBadges
        FROM Badges b
        GROUP BY b.UserId
    ),
    recent_activity AS (
        SELECT
            u.Id                                   AS UserId,
            MAX(p.CreationDate)   AS LastPostDate,
            MAX(v.CreationDate)   AS LastVoteDate,
            MAX(c.CreationDate)   AS LastCommentDate
        FROM Users u
        LEFT JOIN Posts    p ON p.OwnerUserId = u.Id
        LEFT JOIN Votes    v ON v.UserId     = u.Id
        LEFT JOIN Comments c ON c.UserId     = u.Id
        GROUP BY u.Id
    ),
    post_agg AS (
        SELECT
            OwnerUserId                     AS UserId,
            COUNT(*)                        AS TotalPosts,
            COUNT(*) FILTER (WHERE PostTypeId = 1) AS TotalQuestions,
            COUNT(*) FILTER (WHERE PostTypeId = 2) AS TotalAnswers,
            AVG(Score)::NUMERIC(10,2)       AS AvgScore
        FROM Posts
        WHERE OwnerUserId IS NOT NULL
        GROUP BY OwnerUserId
    )
-- First branch: users with activity (or high reputation)
SELECT
    u.Id                                   AS UserId,
    u.DisplayName,
    u.Reputation,
    COALESCE(pa.TotalPosts,0)               AS TotalPosts,
    COALESCE(pa.TotalQuestions,0)           AS TotalQuestions,
    COALESCE(pa.TotalAnswers,0)             AS TotalAnswers,
    COALESCE(pa.AvgScore,0)                 AS AvgPostScore,
    COALESCE(ub.GoldBadges,0)               AS GoldBadges,
    COALESCE(ub.SilverBadges,0)             AS SilverBadges,
    COALESCE(ub.BronzeBadges,0)             AS BronzeBadges,
    COALESCE(ra.LastPostDate, TIMESTAMP '1900-01-01')     AS LastPostDate,
    COALESCE(ra.LastVoteDate, TIMESTAMP '1900-01-01')     AS LastVoteDate,
    COALESCE(ra.LastCommentDate, TIMESTAMP '1900-01-01') AS LastCommentDate,
    STRING_AGG(
        tt.Tag || ':' || tt.TagUseCount::TEXT,
        ', '
    ) FILTER (WHERE tt.rn <= 3)            AS Top3Tags
FROM Users u
LEFT JOIN post_agg pa        ON pa.UserId = u.Id
LEFT JOIN user_badges ub    ON ub.UserId = u.Id
LEFT JOIN recent_activity ra ON ra.UserId = u.Id
LEFT JOIN top_tags tt       ON tt.UserId = u.Id AND tt.rn <= 3
WHERE (u.Reputation > 1000 OR pa.TotalPosts IS NOT NULL)
GROUP BY
    u.Id, u.DisplayName, u.Reputation,
    pa.TotalPosts, pa.TotalQuestions, pa.TotalAnswers, pa.AvgScore,
    ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges,
    ra.LastPostDate, ra.LastVoteDate, ra.LastCommentDate
HAVING COUNT(*) FILTER (WHERE tt.rn = 1) > 0

UNION ALL

-- Second branch: users without any posts (to stress outer‑join handling)
SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    0,0,0,0,
    0,0,0,
    NULL,NULL,NULL,
    NULL
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)

ORDER BY Reputation DESC, UserId
LIMIT 100;
