-- {"query": "3664.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1722}
WITH
user_badge_counts AS (
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_cnt,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_cnt,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_cnt
    FROM Badges b
    GROUP BY b.UserId
),
user_post_stats AS (
    SELECT
        p.OwnerUserId                                          AS user_id,
        COUNT(*) FILTER (WHERE pt.Name = 'Question')           AS question_cnt,
        COUNT(*) FILTER (WHERE pt.Name = 'Answer')             AS answer_cnt,
        COALESCE(MAX(p.LastActivityDate), MIN(p.CreationDate)) AS last_activity,
        AVG(p.Score)                                           AS avg_score,
        STRING_AGG(DISTINCT TRIM(BOTH '<>' FROM t.tag), ', ')  AS tag_list
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN LATERAL (
        SELECT UNNEST(STRING_TO_ARRAY(p.Tags, '><')) AS tag
    ) t ON TRUE
    WHERE p.PostTypeId = 1
    GROUP BY p.OwnerUserId
),
user_vote_profile AS (
    SELECT
        v.UserId                                 AS user_id,
        COUNT(*) FILTER (WHERE vt.Name = 'UpMod')   AS up_votes,
        COUNT(*) FILTER (WHERE vt.Name = 'DownMod') AS down_votes,
        MAX(v.CreationDate)                         AS last_vote_date,
        ROW_NUMBER() OVER (ORDER BY COUNT(*) FILTER (WHERE vt.Name = 'UpMod') DESC) AS vote_rank
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY v.UserId
),
post_comment_delta AS (
    SELECT
        p.Id                                     AS post_id,
        p.OwnerUserId                            AS user_id,
        COALESCE(
            (SELECT COUNT(*)
             FROM Comments c
             WHERE c.PostId = p.Id
               AND (p.LastEditDate IS NULL OR c.CreationDate > p.LastEditDate)
            ), 0)                               AS comments_after_last_edit
    FROM Posts p
),
top_by_rep AS (
    SELECT u.Id AS user_id, u.Reputation
    FROM Users u
    ORDER BY u.Reputation DESC
    LIMIT 100
),
top_by_activity AS (
    SELECT ups.user_id, ups.last_activity
    FROM user_post_stats ups
    WHERE ups.last_activity >= CAST('2024-10-01' AS date) - INTERVAL '30 days'
    ORDER BY ups.last_activity DESC
    LIMIT 100
),
elite_users AS (
    SELECT t1.user_id
    FROM top_by_rep t1
    INTERSECT
    SELECT t2.user_id
    FROM top_by_activity t2
),
final_report AS (
    SELECT
        u.Id                                    AS user_id,
        u.DisplayName,
        u.Reputation,
        COALESCE(ubc.gold_cnt,0)                AS gold_badges,
        COALESCE(ubc.silver_cnt,0)              AS silver_badges,
        COALESCE(ubc.bronze_cnt,0)              AS bronze_badges,
        COALESCE(ups.question_cnt,0)            AS total_questions,
        COALESCE(ups.answer_cnt,0)              AS total_answers,
        ROUND(CAST(ups.avg_score AS numeric),2) AS average_post_score,
        ups.tag_list,
        uvp.up_votes,
        uvp.down_votes,
        uvp.vote_rank,
        pcd.comments_after_last_edit,
        CASE
            WHEN u.Reputation >= 20000 THEN 'Legendary'
            WHEN u.Reputation BETWEEN 10000 AND 19999 THEN 'Veteran'
            WHEN u.Reputation BETWEEN 5000 AND 9999 THEN 'Experienced'
            ELSE 'Rising'
        END                                      AS reputation_tier,
        CASE WHEN eu.user_id IS NOT NULL THEN TRUE ELSE FALSE END AS is_elite
    FROM Users u
    LEFT JOIN user_badge_counts ubc      ON ubc.UserId = u.Id
    LEFT JOIN user_post_stats ups        ON ups.user_id = u.Id
    LEFT JOIN user_vote_profile uvp      ON uvp.user_id = u.Id
    LEFT JOIN post_comment_delta pcd     ON pcd.user_id = u.Id
    LEFT JOIN elite_users eu             ON eu.user_id = u.Id
)
SELECT *
FROM final_report
ORDER BY reputation_tier DESC, Reputation DESC
LIMIT 50;