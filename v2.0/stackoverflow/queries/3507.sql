-- {"query": "3507.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1811}
WITH user_posts AS (
    SELECT 
        u.Id               AS user_id,
        u.DisplayName,
        p.Id               AS post_id,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        p.ViewCount,
        p.FavoriteCount,
        p.Tags,
        p.AcceptedAnswerId,
        p.ParentId
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
),
post_agg AS (
    SELECT 
        up.user_id,
        COUNT(CASE WHEN up.PostTypeId = 1 THEN 1 END)                                   AS question_cnt,
        COUNT(CASE WHEN up.PostTypeId = 2 THEN 1 END)                                   AS answer_cnt,
        AVG(CASE WHEN up.PostTypeId IN (1,2) THEN up.Score END)                         AS avg_score,
        CASE WHEN COUNT(CASE WHEN up.PostTypeId = 1 THEN 1 END) = 0 THEN NULL
             ELSE 1.0 * SUM(CASE WHEN up.PostTypeId = 1 AND up.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) / COUNT(CASE WHEN up.PostTypeId = 1 THEN 1 END)
        END                                                                               AS accept_rate
    FROM user_posts up
    GROUP BY up.user_id
),
tag_usage AS (
    SELECT 
        up.user_id,
        TRIM(BOTH '<>' FROM t)                         AS tag,
        COUNT(*)                                       AS tag_cnt
    FROM user_posts up
    CROSS JOIN LATERAL (
        SELECT UNNEST(string_to_array(up.Tags, '><')) AS t
    ) s
    WHERE up.Tags IS NOT NULL
    GROUP BY up.user_id, TRIM(BOTH '<>' FROM t)
),
top_tag_per_user AS (
    SELECT 
        user_id,
        tag,
        tag_cnt,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY tag_cnt DESC) AS rn
    FROM tag_usage
),
badge_summary AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 3
                 WHEN b.Class = 2 THEN 2
                 ELSE 1 END)                                   AS badge_score,
        COUNT(*)                                            AS badge_cnt
    FROM Badges b
    GROUP BY b.UserId
),
vote_agg AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1
                 WHEN v.VoteTypeId = 3 THEN -1
                 ELSE 0 END)                                   AS net_votes
    FROM Votes v
    GROUP BY v.PostId
),
user_vote_summary AS (
    SELECT 
        up.user_id,
        COALESCE(SUM(v.net_votes),0)                        AS total_net_votes
    FROM user_posts up
    LEFT JOIN vote_agg v ON v.PostId = up.post_id
    GROUP BY up.user_id
),
recent_activity AS (
    SELECT 
        u.Id                                                AS user_id,
        MAX(p.CreationDate)                                 AS last_post_dt
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id
),
final_set AS (
    SELECT 
        u.Id                        AS user_id,
        u.DisplayName,
        pa.question_cnt,
        pa.answer_cnt,
        pa.avg_score,
        pa.accept_rate,
        ra.last_post_dt,
        bs.badge_score,
        bs.badge_cnt,
        uv.total_net_votes,
        tt.tag,
        tt.tag_cnt
    FROM Users u
    LEFT JOIN post_agg pa            ON pa.user_id = u.Id
    LEFT JOIN recent_activity ra    ON ra.user_id = u.Id
    LEFT JOIN badge_summary bs      ON bs.UserId = u.Id
    LEFT JOIN user_vote_summary uv  ON uv.user_id = u.Id
    LEFT JOIN top_tag_per_user tt   ON tt.user_id = u.Id AND tt.rn = 1
)
-- Combine three result sets using UNION ALL and EXCEPT. To ensure compatibility across dialects,
-- we explicitly list columns in the same order for each branch.
SELECT user_id,
       DisplayName,
       question_cnt,
       answer_cnt,
       avg_score,
       accept_rate,
       last_post_dt,
       badge_score,
       badge_cnt,
       total_net_votes,
       tag,
       tag_cnt
FROM final_set
WHERE question_cnt > 10
  AND avg_score IS NOT NULL

UNION ALL

SELECT user_id,
       DisplayName,
       question_cnt,
       answer_cnt,
       avg_score,
       accept_rate,
       last_post_dt,
       badge_score,
       badge_cnt,
       total_net_votes,
       tag,
       tag_cnt
FROM final_set
WHERE tag IS NULL
  AND badge_cnt IS NULL

EXCEPT

SELECT user_id,
       DisplayName,
       question_cnt,
       answer_cnt,
       avg_score,
       accept_rate,
       last_post_dt,
       badge_score,
       badge_cnt,
       total_net_votes,
       tag,
       tag_cnt
FROM final_set
WHERE total_net_votes < 0
ORDER BY avg_score DESC NULLS LAST, user_id DESC
LIMIT 110;