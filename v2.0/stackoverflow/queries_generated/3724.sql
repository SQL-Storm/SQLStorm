-- {"query": "3724.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2347} 

WITH
    recent_votes AS (
        SELECT v.UserId,
               COUNT(*) AS vote_cnt
        FROM   Votes v
        WHERE  v.CreationDate >= CURRENT_DATE - INTERVAL '30 day'
        GROUP  BY v.UserId
    ),

    post_agg AS (
        SELECT
            p.OwnerUserId                         AS user_id,
            COUNT(*) FILTER (WHERE p.PostTypeId = 1)  AS question_cnt,
            COUNT(*) FILTER (WHERE p.PostTypeId = 2)  AS answer_cnt,
            SUM(p.Score)                           AS total_score,
            MAX(p.CreationDate)                    AS last_post_date,
            /* count distinct tags across all posts of a user */
            COUNT(DISTINCT t.tag)                  AS distinct_tag_cnt
        FROM   Posts p
        LEFT JOIN LATERAL (
            SELECT UNNEST(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS tag
        ) t ON true
        WHERE  p.OwnerUserId IS NOT NULL
        GROUP  BY p.OwnerUserId
    ),

    badge_agg AS (
        SELECT
            b.UserId,
            COUNT(*) FILTER (WHERE b.Class = 1) AS gold_badge_cnt,
            COUNT(*) FILTER (WHERE b.Class = 2) AS silver_badge_cnt,
            COUNT(*) FILTER (WHERE b.Class = 3) AS bronze_badge_cnt
        FROM   Badges b
        GROUP  BY b.UserId
    ),

    user_rank AS (
        SELECT
            u.Id,
            u.DisplayName,
            COALESCE(pa.question_cnt,0) + COALESCE(pa.answer_cnt,0) AS total_posts,
            ROW_NUMBER() OVER (ORDER BY COALESCE(pa.total_score,0) DESC, u.Reputation DESC) AS score_rank,
            LAG(u.Reputation)   OVER (ORDER BY u.Reputation DESC) AS prev_rep,
            LEAD(u.Reputation)  OVER (ORDER BY u.Reputation DESC) AS next_rep
        FROM   Users u
        LEFT JOIN post_agg pa ON pa.user_id = u.Id
    )

SELECT
    ur.Id,
    ur.DisplayName,
    ur.total_posts,
    ur.score_rank,
    ur.prev_rep,
    ur.next_rep,
    COALESCE(pa.question_cnt,0)               AS questions,
    COALESCE(pa.answer_cnt,0)                 AS answers,
    COALESCE(pa.total_score,0)                AS total_score,
    COALESCE(pa.last_post_date, TIMESTAMP '1970-01-01') AS last_post,
    COALESCE(pa.distinct_tag_cnt,0)           AS tag_variety,
    COALESCE(b.gold_badge_cnt,0)              AS gold_badges,
    COALESCE(b.silver_badge_cnt,0)            AS silver_badges,
    COALESCE(b.bronze_badge_cnt,0)            AS bronze_badges,
    COALESCE(rv.vote_cnt,0)                   AS recent_votes,
    CASE
        WHEN u.CreationDate < CURRENT_DATE - INTERVAL '5 year' THEN 'Veteran'
        WHEN u.CreationDate > CURRENT_DATE - INTERVAL '1 year' THEN 'Newbie'
        ELSE 'Regular'
    END                                        AS user_cohort,
    CASE
        WHEN ur.score_rank <= 10   THEN 'Top10'
        WHEN ur.score_rank <= 100  THEN 'Top100'
        ELSE 'Other'
    END                                        AS rank_bucket
FROM   user_rank ur
LEFT JOIN post_agg   pa ON pa.user_id = ur.Id
LEFT JOIN badge_agg  b  ON b.UserId = ur.Id
LEFT JOIN recent_votes rv ON rv.UserId = ur.Id
LEFT JOIN Users u ON u.Id = ur.Id
WHERE  (ur.score_rank <= 200 OR ur.total_posts > 0)

UNION ALL

SELECT
    -1                                         AS Id,
    'Aggregated Totals'                         AS DisplayName,
    SUM(ur.total_posts)                        AS total_posts,
    NULL                                        AS score_rank,
    NULL                                        AS prev_rep,
    NULL                                        AS next_rep,
    SUM(COALESCE(pa.question_cnt,0))            AS questions,
    SUM(COALESCE(pa.answer_cnt,0))              AS answers,
    SUM(COALESCE(pa.total_score,0))             AS total_score,
    MAX(COALESCE(pa.last_post_date, TIMESTAMP '1970-01-01')) AS last_post,
    SUM(COALESCE(pa.distinct_tag_cnt,0))        AS tag_variety,
    SUM(COALESCE(b.gold_badge_cnt,0))           AS gold_badges,
    SUM(COALESCE(b.silver_badge_cnt,0))         AS silver_badges,
    SUM(COALESCE(b.bronze_badge_cnt,0))         AS bronze_badges,
    SUM(COALESCE(rv.vote_cnt,0))                AS recent_votes,
    NULL                                        AS user_cohort,
    NULL                                        AS rank_bucket
FROM   user_rank ur
LEFT JOIN post_agg   pa ON pa.user_id = ur.Id
LEFT JOIN badge_agg  b  ON b.UserId = ur.Id
LEFT JOIN recent_votes rv ON rv.UserId = ur.Id
WHERE  ur.score_rank <= 200
ORDER BY score_rank NULLS LAST;
