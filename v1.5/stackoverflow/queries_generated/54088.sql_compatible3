WITH
user_stats AS (
    SELECT
        u.Id AS user_id,
        u.DisplayName,
        u.Reputation,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS question_cnt,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS answer_cnt,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS avg_q_score,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS avg_a_score,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS upvote_cnt,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS downvote_cnt
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
tag_user_links AS (
    SELECT
        u.Id AS user_id,
        t.tag_name,
        COUNT(*) AS tag_use_cnt
    FROM Users u
    JOIN Posts p
        ON p.OwnerUserId = u.Id
        AND p.PostTypeId = 1
    JOIN (
        SELECT CAST(value AS VARCHAR) AS tag_name
        FROM (
            SELECT unnest(string_to_array(p.Tags, '<>')) AS value
        ) AS s
        WHERE value <> ''
    ) AS t ON TRUE
    GROUP BY u.Id, t.tag_name
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
        a.Id AS answer_id,
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
    ROUND(us.avg_q_score, 2) AS avg_q_score,
    ROUND(us.avg_a_score, 2) AS avg_a_score,
    us.upvote_cnt,
    us.downvote_cnt,
    COALESCE(tt.tags, '') AS top_tags,
    ar.answer_id AS top_answer_for_question,
    ar.Score AS top_answer_score
FROM user_stats us
LEFT JOIN top_tags tt ON tt.user_id = us.user_id
LEFT JOIN Posts p ON p.OwnerUserId = us.user_id AND p.PostTypeId = 1
LEFT JOIN answer_rank ar ON ar.question_id = p.Id AND ar.rn = 1
ORDER BY us.Reputation DESC
LIMIT 100;