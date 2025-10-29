-- {"query": "3375.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2277}
WITH UserStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id)                                   AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)           AS GoldBadges,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC)         AS RepRank
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostMetrics AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        COALESCE(p.Tags, '')                                    AS Tags,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCnt,
        (SELECT MAX(ph.CreationDate)
         FROM PostHistory ph
         WHERE ph.PostId = p.Id)                               AS LastEdit,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId
                           ORDER BY p.Score DESC, p.CreationDate) AS ScoreRank
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
TagExploded AS (
    SELECT
        pm.Id AS PostId,
        -- use regexp or string functions to split tags in a more portable way
        TRIM(tag) AS Tag
    FROM PostMetrics pm,
    LATERAL (
      SELECT CASE
               WHEN pm.Tags = '' THEN NULL
               ELSE split_part(split_part(pm.Tags, '><', n.n), '><', 1)
             END AS tag
      FROM (
        SELECT generate_series(1, 100) AS n  -- adjust upper bound as needed
      ) n
      WHERE pm.Tags <> ''
        AND n.n <= 1 + LENGTH(pm.Tags) - LENGTH(REPLACE(pm.Tags, '><', ''))
    ) s
    WHERE pm.Tags <> ''
),
TagStats AS (
    SELECT
        te.Tag,
        COUNT(DISTINCT te.PostId)                                   AS PostsPerTag,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END)          AS QuestionsPerTag,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END)          AS AnswersPerTag
    FROM TagExploded te
    JOIN Posts p ON p.Id = te.PostId
    GROUP BY te.Tag
),
VoteAgg AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)          AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)          AS DownVotes,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END)          AS Favorites
    FROM Votes v
    GROUP BY v.PostId
)
SELECT
    'Question'                                                       AS EntityType,
    p.Id,
    p.Title,
    us.DisplayName,
    us.Reputation,
    us.RepRank,
    p.Score,
    p.ViewCount,
    p.CommentCnt,
    p.LastEdit,
    v.UpVotes,
    v.DownVotes,
    v.Favorites,
    COALESCE(t.PostsPerTag, 0)                                        AS TotalPostsWithTag,
    COALESCE(t.QuestionsPerTag, 0)                                    AS TotalQuestionsWithTag,
    COALESCE(t.AnswersPerTag, 0)                                      AS TotalAnswersPerTag,
    CASE WHEN p.Score < 0 THEN 'NegativeScore' ELSE 'NonNegative' END AS ScoreCategory,
    CASE WHEN p.Tags IS NULL OR p.Tags = '' THEN 'Untagged' ELSE 'Tagged' END AS TagPresence,
    p.PostTypeId,
    p.CreationDate
FROM PostMetrics p
JOIN UserStats us          ON us.Id = p.OwnerUserId
LEFT JOIN VoteAgg v       ON v.PostId = p.Id
LEFT JOIN TagStats t
       ON EXISTS (
         SELECT 1
         FROM TagExploded te2
         WHERE te2.Tag = t.Tag
           AND te2.PostId = p.Id
       )
WHERE p.PostTypeId = 1
  AND p.ScoreRank <= 10

UNION ALL

SELECT
    'Answer'                                                         AS EntityType,
    p.Id,
    COALESCE(q.Title, 'NoQuestion')                                  AS Title,
    us.DisplayName,
    us.Reputation,
    us.RepRank,
    p.Score,
    NULL                                                             AS ViewCount,
    p.CommentCnt,
    p.LastEdit,
    v.UpVotes,
    v.DownVotes,
    v.Favorites,
    NULL                                                             AS TotalPostsWithTag,
    NULL                                                             AS TotalQuestionsWithTag,
    NULL                                                             AS TotalAnswersPerTag,
    CASE WHEN p.Score < 0 THEN 'NegativeScore' ELSE 'NonNegative' END AS ScoreCategory,
    'N/A'                                                            AS TagPresence,
    p.PostTypeId,
    p.CreationDate
FROM PostMetrics p
LEFT JOIN Posts q        ON q.Id = p.Id
JOIN UserStats us       ON us.Id = p.OwnerUserId
LEFT JOIN VoteAgg v    ON v.PostId = p.Id
WHERE p.PostTypeId = 2
  AND p.ScoreRank <= 5

ORDER BY EntityType,
         Score DESC,
         CreationDate DESC
LIMIT 100;