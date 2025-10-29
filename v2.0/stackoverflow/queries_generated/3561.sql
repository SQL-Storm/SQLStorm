-- {"query": "3561.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2322} 

WITH q_posts AS (
    SELECT 
        p.Id,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.AnswerCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn_q
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CURRENT_DATE - INTERVAL '90 days'
      AND (
            p.Score > 10 
            OR p.ViewCount > 5000 
            OR p.Tags ILIKE '%<sql>%'
          )
),
a_posts AS (
    SELECT 
        p.Id,
        p.ParentId AS QuestionId,
        p.CreationDate,
        p.Score,
        p.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn_a
    FROM Posts p
    WHERE p.PostTypeId = 2
      AND p.CreationDate >= CURRENT_DATE - INTERVAL '90 days'
),
user_badges AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS gold,
        COUNT(*) FILTER (WHERE b.Class = 2) AS silver,
        COUNT(*) FILTER (WHERE b.Class = 3) AS bronze,
        MAX(b.Date) AS last_badge_date
    FROM Badges b
    GROUP BY b.UserId
),
user_votes AS (
    SELECT 
        v.UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS up_votes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS down_votes,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 5) AS favorites
    FROM Votes v
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '180 days'
    GROUP BY v.UserId
),
post_comments_cnt AS (
    SELECT 
        c.PostId,
        COUNT(*) AS comment_cnt,
        MAX(c.CreationDate) AS last_comment_date
    FROM Comments c
    GROUP BY c.PostId
)

SELECT
    u.Id                              AS UserId,
    COALESCE(u.DisplayName,'Anonymous') AS DisplayName,
    u.Reputation,
    ub.gold,
    ub.silver,
    ub.bronze,
    uv.up_votes,
    uv.down_votes,
    uv.favorites,
    q.Id                              AS QuestionId,
    q.Title,
    q.Score                           AS QuestionScore,
    q.ViewCount,
    q.Tags,
    a.Id                              AS TopAnswerId,
    a.Score                           AS AnswerScore,
    pc.comment_cnt,
    pc.last_comment_date,
    CASE
        WHEN q.AnswerCount = 0                     THEN 'Unanswered'
        WHEN a.rn_a = 1                            THEN 'HasBestAnswer'
        ELSE                                        'HasAnswers'
    END                                 AS AnswerStatus,
    COALESCE(
        (SELECT json_agg(json_build_object('tag',trim(both '<>' from t)))
         FROM regexp_split_to_table(q.Tags,'><') AS t),
        '[]'
    )                                   AS TagArrayJson,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY q.CreationDate DESC) AS QuestionRank
FROM Users u
LEFT JOIN user_badges ub       ON ub.UserId = u.Id
LEFT JOIN user_votes uv        ON uv.UserId = u.Id
LEFT JOIN q_posts q            ON q.OwnerUserId = u.Id AND q.rn_q <= 5
LEFT JOIN a_posts a            ON a.QuestionId = q.Id AND a.rn_a = 1
LEFT JOIN post_comments_cnt pc ON pc.PostId = q.Id
WHERE u.Reputation > 1000
  AND (ub.gold > 0 OR uv.up_votes > 100)

UNION ALL

SELECT
    u.Id,
    COALESCE(u.DisplayName,'Anonymous'),
    u.Reputation,
    ub.gold,
    ub.silver,
    ub.bronze,
    uv.up_votes,
    uv.down_votes,
    uv.favorites,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    'NoQuestion'                     AS AnswerStatus,
    '[]'::json                        AS TagArrayJson,
    NULL
FROM Users u
LEFT JOIN user_badges ub ON ub.UserId = u.Id
LEFT JOIN user_votes uv  ON uv.UserId = u.Id
WHERE NOT EXISTS (SELECT 1 FROM q_posts qp WHERE qp.OwnerUserId = u.Id)
  AND u.Reputation BETWEEN 500 AND 1000

ORDER BY Reputation DESC NULLS LAST,
         QuestionScore DESC NULLS LAST
LIMIT 200;
