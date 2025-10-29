-- {"query": "3886.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3493}
WITH
user_stats AS (
    SELECT
        u.Id                                     AS user_id,
        u.DisplayName                            AS display_name,
        u.Reputation,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END)  AS question_cnt,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END)  AS answer_cnt,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS up_votes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS down_votes,
        MAX(p.CreationDate)                     AS last_post_dt
    FROM Users u
    LEFT JOIN Posts  p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes  v ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
badge_counts AS (
    SELECT
        b.UserId                                   AS user_id,
        COUNT(*)                                   AS badge_total,
        COUNT(*) FILTER (WHERE b.Class = 1)        AS gold_cnt,
        COUNT(*) FILTER (WHERE b.Class = 2)        AS silver_cnt,
        COUNT(*) FILTER (WHERE b.Class = 3)        AS bronze_cnt
    FROM Badges b
    GROUP BY b.UserId
),
raw_tag_usage AS (
    SELECT
        p.OwnerUserId                              AS user_id,
        TRIM(BOTH '>' FROM
            UNNEST(string_to_array(
                substring(p.Tags, 2, length(p.Tags)-2), '><'))) AS tag
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
),
tag_aggregated AS (
    SELECT
        user_id,
        tag,
        COUNT(*) AS tag_cnt,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY COUNT(*) DESC) AS rn
    FROM raw_tag_usage
    GROUP BY user_id, tag
),
top_tags AS (
    SELECT
        user_id,
        STRING_AGG(tag, ', ') AS top_3_tags
    FROM tag_aggregated
    WHERE rn <= 3
    GROUP BY user_id
),
user_ranking AS (
    SELECT
        us.user_id,
        RANK() OVER (ORDER BY us.Reputation DESC)           AS rep_rank,
        PERCENT_RANK() OVER (ORDER BY us.Reputation)       AS rep_percentile
    FROM user_stats us
),
union_users AS (
    SELECT
        us.user_id,
        us.display_name,
        us.Reputation,
        us.question_cnt,
        us.answer_cnt,
        us.up_votes,
        us.down_votes,
        us.last_post_dt,
        bc.badge_total,
        bc.gold_cnt,
        bc.silver_cnt,
        bc.bronze_cnt,
        tt.top_3_tags,
        ur.rep_rank,
        ur.rep_percentile,
        1                                            AS is_active
    FROM user_stats us
    LEFT JOIN badge_counts bc ON bc.user_id = us.user_id
    LEFT JOIN top_tags tt     ON tt.user_id = us.user_id
    LEFT JOIN user_ranking ur ON ur.user_id = us.user_id
    WHERE us.question_cnt > 0

    UNION ALL

    SELECT
        us.user_id,
        us.display_name,
        us.Reputation,
        us.question_cnt,
        us.answer_cnt,
        us.up_votes,
        us.down_votes,
        us.last_post_dt,
        bc.badge_total,
        bc.gold_cnt,
        bc.silver_cnt,
        bc.bronze_cnt,
        tt.top_3_tags,
        ur.rep_rank,
        ur.rep_percentile,
        0                                            AS is_active
    FROM user_stats us
    LEFT JOIN badge_counts bc ON bc.user_id = us.user_id
    LEFT JOIN top_tags tt     ON tt.user_id = us.user_id
    LEFT JOIN user_ranking ur ON ur.user_id = us.user_id
    WHERE us.question_cnt = 0
)

SELECT
    u.user_id,
    u.display_name,
    u.Reputation,
    u.rep_rank,
    ROUND(CAST(u.rep_percentile * 100.0 AS numeric), 2) AS rep_pct,
    u.question_cnt,
    u.answer_cnt,
    (u.up_votes - u.down_votes)                AS net_score,
    (SELECT ROUND(AVG(CAST(a.Score AS numeric)), 2)
     FROM Posts a
     WHERE a.PostTypeId = 2
       AND a.OwnerUserId = u.user_id)          AS avg_answer_score,
    u.last_post_dt,
    COALESCE(u.badge_total,0)                  AS total_badges,
    COALESCE(u.gold_cnt,0)                     AS gold_badges,
    COALESCE(u.silver_cnt,0)                   AS silver_badges,
    COALESCE(u.bronze_cnt,0)                   AS bronze_badges,
    COALESCE(u.top_3_tags,'')                  AS top_tags,
    CASE
        WHEN u.Reputation >= 20000 THEN 'Legendary'
        WHEN u.Reputation >= 10000 THEN 'Elite'
        WHEN u.Reputation >= 5000  THEN 'Pro'
        WHEN u.Reputation >= 1000  THEN 'Intermediate'
        ELSE 'Novice'
    END                                          AS reputation_level,
    u.is_active,
    (u.question_cnt*0.15 + u.answer_cnt*0.25 +
     COALESCE(u.gold_cnt,0)*5 + COALESCE(u.silver_cnt,0)*2 +
     (u.up_votes - u.down_votes)*0.01)        AS composite_score
FROM union_users u
WHERE u.is_active = 1
GROUP BY
    u.user_id,
    u.display_name,
    u.Reputation,
    u.rep_rank,
    u.rep_percentile,
    u.question_cnt,
    u.answer_cnt,
    u.up_votes,
    u.down_votes,
    u.last_post_dt,
    u.badge_total,
    u.gold_cnt,
    u.silver_cnt,
    u.bronze_cnt,
    u.top_3_tags,
    u.is_active
ORDER BY composite_score DESC, u.Reputation DESC
LIMIT 100;