WITH
user_stats AS (
    SELECT
        u.Id                     AS user_id,
        u.DisplayName,
        u.Reputation,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS question_cnt,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answer_cnt,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS avg_q_score,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS avg_a_score,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN v.Id END)   AS upvote_cnt,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN v.Id END)   AS downvote_cnt
    FROM Users u
    LEFT JOIN Posts  p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes  v ON v.PostId     = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
tag_user_links AS (
    /* portable tag splitting: replace '><' with '|' then split by '|' using a recursive CTE */
    SELECT
        u.Id                 AS user_id,
        TRIM(BOTH '<>' FROM part) AS tag_name,
        COUNT(*)            AS tag_use_cnt
    FROM Users u
    JOIN Posts p
        ON p.OwnerUserId = u.Id
        AND p.PostTypeId = 1
    CROSS JOIN LATERAL (
        WITH RECURSIVE split(rest, part) AS (
            SELECT
                regexp_replace(p.Tags, '><', '|') || '' ,
                CASE
                  WHEN POSITION('|' IN regexp_replace(p.Tags, '><', '|')) > 0 THEN SUBSTRING(regexp_replace(p.Tags, '><', '|') FROM 1 FOR POSITION('|' IN regexp_replace(p.Tags, '><', '|'))-1)
                  WHEN regexp_replace(p.Tags, '><', '|') <> '' THEN regexp_replace(p.Tags, '><', '|')
                  ELSE NULL
                END
            UNION ALL
            SELECT
                CASE WHEN POSITION('|' IN rest) > 0 THEN SUBSTRING(rest FROM POSITION('|' IN rest)+1) ELSE '' END,
                CASE WHEN POSITION('|' IN rest) > 0 THEN SUBSTRING(rest FROM 1 FOR POSITION('|' IN rest)-1)
                     WHEN rest <> '' THEN rest
                     ELSE NULL END
            FROM split
            WHERE rest <> ''
        )
        SELECT part FROM split WHERE part IS NOT NULL
    ) toks
    GROUP BY u.Id, TRIM(BOTH '<>' FROM part)
),
top_tags AS (
    SELECT
        user_id,
        STRING_AGG(tag_name || ':' || tag_use_cnt, ',') AS tags
    FROM tag_user_links
    GROUP BY user_id
),
answer_rank AS (
    SELECT
        a.ParentId AS question_id,
        a.Id       AS answer_id,
        a.Score,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS rn
    FROM Posts a
    WHERE a.PostTypeId = 2
)
SELECT
    us.user_id,
    us.DisplayName,
    us.Reputation,
    us.question_cnt,
    us.answer_cnt,
    ROUND(CAST(us.avg_q_score AS NUMERIC), 2)   AS avg_q_score,
    ROUND(CAST(us.avg_a_score AS NUMERIC), 2)   AS avg_a_score,
    us.upvote_cnt,
    us.downvote_cnt,
    COALESCE(tt.tags, '')     AS top_tags,
    ar.answer_id              AS top_answer_for_question,
    ar.Score                  AS top_answer_score
FROM user_stats      us
LEFT JOIN top_tags      tt ON tt.user_id      = us.user_id
LEFT JOIN Posts  p       ON p.OwnerUserId   = us.user_id
                         AND p.PostTypeId   = 1
LEFT JOIN answer_rank ar ON ar.question_id  = p.Id
                         AND ar.rn           = 1
GROUP BY
    us.user_id,
    us.DisplayName,
    us.Reputation,
    us.question_cnt,
    us.answer_cnt,
    us.avg_q_score,
    us.avg_a_score,
    us.upvote_cnt,
    us.downvote_cnt,
    tt.tags,
    ar.answer_id,
    ar.Score
ORDER BY us.Reputation DESC
LIMIT 100;