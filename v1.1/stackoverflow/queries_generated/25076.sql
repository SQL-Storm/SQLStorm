-- {"query": "25076.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2559} 

/*  Complex benchmark query on the StackOverflow schema  */
WITH
    /* Aggregate posts per user */
    user_posts AS (
        SELECT
            u.Id                                   AS user_id,
            COUNT(p.Id)                            AS post_cnt,
            COALESCE(SUM(p.Score),0)               AS total_score,
            ROUND(AVG(p.Score)::numeric,2)         AS avg_score,
            COALESCE(SUM(p.ViewCount),0)           AS total_views,
            MAX(p.CreationDate)                    AS last_post_dt,
            COUNT(DISTINCT ph.Comment) FILTER (WHERE ph.PostHistoryTypeId = 10) AS close_vote_cnt
        FROM Users u
        LEFT JOIN Posts p          ON p.OwnerUserId = u.Id
        LEFT JOIN PostHistory ph  ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
        GROUP BY u.Id
    ),

    /* Badge statistics per user */
    user_badges AS (
        SELECT
            b.UserId                               AS user_id,
            COUNT(*)                               AS badge_cnt,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_cnt,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_cnt,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_cnt,
            MAX(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END) AS has_tag_badge
        FROM Badges b
        GROUP BY b.UserId
    ),

    /* Voting activity per user */
    user_votes AS (
        SELECT
            v.UserId                               AS user_id,
            COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS up_votes_given,
            COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS down_votes_given,
            COUNT(*) FILTER (WHERE v.VoteTypeId = 5) AS favorites_given
        FROM Votes v
        GROUP BY v.UserId
    ),

    /* Latest comment per user with a short sample */
    user_comments AS (
        SELECT
            c.UserId                               AS user_id,
            MAX(c.CreationDate)                    AS last_comment_dt,
            STRING_AGG(SUBSTRING(c.Text FROM 1 FOR 30), '; ') AS sample_comments
        FROM Comments c
        WHERE c.UserId IS NOT NULL
        GROUP BY c.UserId
    )

SELECT
    u.Id                                                            AS user_id,
    u.DisplayName                                                   AS display_name,
    u.Reputation                                                    AS reputation,
    COALESCE(up.post_cnt,0)                                          AS post_cnt,
    up.total_score                                                  AS total_score,
    up.avg_score                                                    AS avg_score,
    up.total_views                                                  AS total_views,
    up.last_post_dt                                                 AS last_post_dt,
    ub.badge_cnt                                                    AS badge_cnt,
    ub.gold_cnt                                                     AS gold_badge_cnt,
    ub.silver_cnt                                                   AS silver_badge_cnt,
    ub.bronze_cnt                                                   AS bronze_badge_cnt,
    CASE WHEN ub.has_tag_badge = 1 THEN 'Yes' ELSE 'No' END         AS has_tag_badge,
    uv.up_votes_given                                               AS up_votes_given,
    uv.down_votes_given                                             AS down_votes_given,
    uv.favorites_given                                              AS favorites_given,
    uc.last_comment_dt                                              AS last_comment_dt,
    uc.sample_comments                                               AS sample_comments,
    RANK() OVER (ORDER BY u.Reputation DESC, up.total_score DESC)  AS reputation_score_rank,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY up.last_post_dt DESC NULLS LAST) AS recent_post_rownum
FROM Users u
LEFT JOIN user_posts    up ON up.user_id = u.Id
LEFT JOIN user_badges   ub ON ub.user_id = u.Id
LEFT JOIN user_votes    uv ON uv.user_id = u.Id
LEFT JOIN user_comments uc ON uc.user_id = u.Id
WHERE
    (u.CreationDate < CURRENT_DATE - INTERVAL '1 year' OR u.CreationDate IS NULL)
    AND (u.Location IS NOT NULL AND u.Location <> '')
    AND (up.post_cnt > 0 OR ub.badge_cnt > 0)
ORDER BY reputation_score_rank
LIMIT 100

UNION ALL

/*  Totals row  */
SELECT
    NULL                     AS user_id,
    'TOTAL'                  AS display_name,
    SUM(u.Reputation)        AS reputation,
    SUM(COALESCE(up.post_cnt,0))          AS post_cnt,
    SUM(COALESCE(up.total_score,0))       AS total_score,
    ROUND(AVG(up.avg_score)::numeric,2)   AS avg_score,
    SUM(COALESCE(up.total_views,0))       AS total_views,
    NULL                     AS last_post_dt,
    SUM(COALESCE(ub.badge_cnt,0))         AS badge_cnt,
    SUM(COALESCE(ub.gold_cnt,0))          AS gold_badge_cnt,
    SUM(COALESCE(ub.silver_cnt,0))        AS silver_badge_cnt,
    SUM(COALESCE(ub.bronze_cnt,0))        AS bronze_badge_cnt,
    NULL                     AS has_tag_badge,
    SUM(COALESCE(uv.up_votes_given,0))    AS up_votes_given,
    SUM(COALESCE(uv.down_votes_given,0))  AS down_votes_given,
    SUM(COALESCE(uv.favorites_given,0))   AS favorites_given,
    NULL                     AS last_comment_dt,
    NULL                     AS sample_comments,
    NULL                     AS reputation_score_rank,
    NULL                     AS recent_post_rownum
FROM Users u
LEFT JOIN user_posts   up ON up.user_id = u.Id
LEFT JOIN user_badges  ub ON ub.user_id = u.Id
LEFT JOIN user_votes   uv ON uv.user_id = u.Id;
