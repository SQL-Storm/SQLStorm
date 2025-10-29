-- {"query": "3226.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1769}
WITH recent_questions AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY)
),
badge_summary AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS gold,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS silver,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS bronze
    FROM Badges b
    GROUP BY b.UserId
),
user_activity AS (
    SELECT
        u.Id                                      AS user_id,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COALESCE(bs.gold,   0)                    AS gold_badges,
        COALESCE(bs.silver, 0)                    AS silver_badges,
        COALESCE(bs.bronze, 0)                    AS bronze_badges,
        (SELECT COUNT(*) FROM Posts p2
         WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1) AS question_cnt,
        (SELECT COUNT(*) FROM Posts p3
         WHERE p3.OwnerUserId = u.Id AND p3.PostTypeId = 2) AS answer_cnt,
        (SELECT AVG(vv.vote_count) FROM (
             SELECT 1 AS vote_count, v.PostId
             FROM Votes v
             WHERE v.VoteTypeId = 2
         ) vv
         JOIN Posts p4 ON vv.PostId = p4.Id
         WHERE p4.OwnerUserId = u.Id) AS avg_upvotes
    FROM Users u
    LEFT JOIN badge_summary bs ON u.Id = bs.UserId
),
tag_stats AS (
    SELECT
        t.TagName,
        COUNT(p.Id)                AS question_cnt,
        SUM(p.Score)               AS total_score,
        AVG(p.ViewCount)           AS avg_views
    FROM Tags t
    JOIN Posts p ON p.PostTypeId = 1
                AND p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    GROUP BY t.TagName
),
top_tags AS (
    SELECT *
    FROM tag_stats
    ORDER BY question_cnt DESC
    LIMIT 10
),
question_rank AS (
    SELECT
        q.Id,
        q.Title,
        q.Score,
        q.ViewCount,
        ROW_NUMBER() OVER (ORDER BY q.Score DESC, q.ViewCount DESC) AS rank_score
    FROM recent_questions q
),
combined AS (
    SELECT
        ua.user_id,
        ua.Reputation,
        ua.gold_badges,
        ua.silver_badges,
        ua.bronze_badges,
        ua.question_cnt,
        ua.answer_cnt,
        ua.avg_upvotes,
        qr.rank_score,
        (SELECT p.OwnerUserId FROM Posts p WHERE p.Id = qr.Id LIMIT 1) AS owner_for_rank
    FROM user_activity ua
    LEFT JOIN question_rank qr
        ON ua.user_id = (SELECT p.OwnerUserId FROM Posts p WHERE p.Id = qr.Id LIMIT 1)
    WHERE ua.Reputation > 10000
)
SELECT
    c.user_id,
    u.DisplayName,
    c.Reputation,
    c.gold_badges,
    c.silver_badges,
    c.bronze_badges,
    c.question_cnt,
    c.answer_cnt,
    ROUND(CAST(c.avg_upvotes AS DECIMAL), 2)       AS avg_upvotes,
    c.rank_score,
    STRING_AGG(DISTINCT tt.TagName, ', ') FILTER (WHERE tt.question_cnt > 5) AS top_tags_used
FROM combined c
JOIN Users u ON c.user_id = u.Id
LEFT JOIN top_tags tt
    ON EXISTS (
        SELECT 1
        FROM Posts p
        WHERE p.OwnerUserId = c.user_id
          AND p.PostTypeId = 1
          AND EXISTS (
              SELECT 1
              FROM (
                -- split tokens by '><' and normalize by removing leading '<' and trailing '>'
                SELECT
                  CASE
                    WHEN LEFT(token,1) = '<' AND RIGHT(token,1) = '>' THEN SUBSTRING(token FROM 2 FOR CHAR_LENGTH(token)-2)
                    WHEN LEFT(token,1) = '<' THEN SUBSTRING(token FROM 2)
                    WHEN RIGHT(token,1) = '>' THEN SUBSTRING(token FROM 1 FOR CHAR_LENGTH(token)-1)
                    ELSE token
                  END AS tname
                FROM (
                  SELECT regexp_split_to_table(p.Tags, '><') AS token
                ) s1
              ) s2
              WHERE s2.tname = tt.TagName
          )
    )
GROUP BY
    c.user_id,
    u.DisplayName,
    c.Reputation,
    c.gold_badges,
    c.silver_badges,
    c.bronze_badges,
    c.question_cnt,
    c.answer_cnt,
    c.avg_upvotes,
    c.rank_score
ORDER BY
    c.rank_score NULLS LAST,
    c.Reputation DESC
LIMIT 100;