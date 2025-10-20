-- {"query": "54021.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 4163} 

WITH post_votes AS (
    SELECT
        p.Id                AS post_id,
        p.OwnerUserId       AS owner_id,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.Id, p.OwnerUserId
),
user_stats AS (
    SELECT
        u.Id          AS user_id,
        u.DisplayName,
        COUNT(p.Id)          AS post_count,
        SUM(p.Score)         AS score_sum,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS question_count,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS answer_count,
        COUNT(b.Id)          AS badge_count,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvote_sum,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvote_sum
    FROM Users u
    LEFT JOIN Posts p      ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b     ON b.UserId = u.Id
    LEFT JOIN Votes v      ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName
),
tag_counts AS (
    SELECT
        p.OwnerUserId,
        trim(both '<>' FROM split_tag) AS tag,
        COUNT(*) AS tag_count
    FROM Posts p
    CROSS JOIN LATERAL regexp_split_to_table(p.Tags, '><') AS split_tag
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId, trim(both '<>' FROM split_tag)
),
top_tag AS (
    SELECT DISTINCT ON (OwnerUserId) OwnerUserId, tag
    FROM (
        SELECT
            OwnerUserId,
            tag,
            ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY tag_count DESC) AS rn
        FROM tag_counts
    ) x
    WHERE rn = 1
)
SELECT
    s.user_id,
    s.DisplayName,
    s.post_count,
    s.score_sum,
    s.question_count,
    s.answer_count,
    s.badge_count,
    s.upvote_sum,
    s.downvote_sum,
    t.tag                     AS top_tag,
    AVG(pv.upvotes) OVER (PARTITION BY s.user_id)   AS avg_post_upvotes,
    SUM(pv.downvotes) OVER (PARTITION BY s.user_id) AS total_post_downvotes,
    COUNT(DISTINCT ph.PostId)                           AS deleted_post_count
FROM user_stats s
LEFT JOIN top_tag t            ON t.OwnerUserId = s.user_id
LEFT JOIN post_votes pv        ON pv.owner_id   = s.user_id
LEFT JOIN PostHistory ph       ON ph.PostId = pv.post_id AND ph.PostHistoryTypeId = 12
WHERE s.post_count > 0
ORDER BY s.score_sum DESC, s.post_count DESC
LIMIT 5000;
