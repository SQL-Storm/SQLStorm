-- {"query": "3478.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3062} 

/*  Benchmarking query – heavy use of CTEs, window functions, outer joins, 
    correlated subqueries, set operators, string ops and NULL logic  */
WITH
    /* per‑user post aggregates */
    user_posts AS (
        SELECT
            u.id                     AS user_id,
            u.displayname            AS display_name,
            COUNT(p.id) FILTER (WHERE p.posttypeid = 1) AS q_cnt,
            COUNT(p.id) FILTER (WHERE p.posttypeid = 2) AS a_cnt,
            SUM(p.score) FILTER (WHERE p.posttypeid = 2) AS a_score_sum,
            AVG(p.score) FILTER (WHERE p.posttypeid = 2) AS a_score_avg
        FROM users u
        LEFT JOIN posts p ON p.owneruserid = u.id
        GROUP BY u.id, u.displayname
    ),

    /* per‑user badge aggregates */
    user_badges AS (
        SELECT
            b.userid                           AS user_id,
            SUM(CASE b.class WHEN 1 THEN 100 WHEN 2 THEN 50 ELSE 25 END) AS badge_pts,
            MAX(b.date)                        AS last_badge_dt,
            STRING_AGG(DISTINCT b.name, ',')
                FILTER (WHERE b.tagbased = 0) AS named_badges,
            STRING_AGG(DISTINCT b.name, ',')
                FILTER (WHERE b.tagbased = 1) AS tag_badges
        FROM badges b
        GROUP BY b.userid
    ),

    /* per‑user vote aggregates (net score, up/down counts) */
    user_votes AS (
        SELECT
            p.owneruserid                         AS user_id,
            SUM(CASE v.votetypeid WHEN 2 THEN 1
                                 WHEN 3 THEN -1 ELSE 0 END) AS net_vote,
            COUNT(*) FILTER (WHERE v.votetypeid = 2) AS up_cnt,
            COUNT(*) FILTER (WHERE v.votetypeid = 3) AS down_cnt
        FROM posts p
        JOIN votes v ON v.postid = p.id
        WHERE p.owneruserid IS NOT NULL
        GROUP BY p.owneruserid
    ),

    /* recent comment activity per user */
    recent_comments AS (
        SELECT
            c.userid                 AS user_id,
            COUNT(*)                 AS cmnt_cnt,
            MAX(c.creationdate)      AS last_cmnt_dt
        FROM comments c
        WHERE c.userid IS NOT NULL
        GROUP BY c.userid
    ),

    /* tag‑level stats */
    tag_stats AS (
        SELECT
            t.tagname               AS tag_name,
            COUNT(p.id)             AS tag_post_cnt,
            SUM(p.score)            AS tag_score,
            STRING_AGG(DISTINCT u.displayname, ',') AS contributors
        FROM tags t
        JOIN posts p ON p.tags LIKE CONCAT('%<', t.tagname, '>%')
        JOIN users u ON u.id = p.owneruserid
        GROUP BY t.tagname
    ),

    /* top‑3 tags per user (using lateral split & window function) */
    top_tags_per_user AS (
        SELECT
            up.user_id,
            tg.tagname,
            ROW_NUMBER() OVER (PARTITION BY up.user_id
                               ORDER BY COUNT(p.id) DESC) AS rn
        FROM user_posts up
        JOIN posts p ON p.owneruserid = up.user_id
        JOIN LATERAL regexp_split_to_table(p.tags, '[><]') AS tg(tag) ON tg.tag <> ''
        JOIN tags tg ON tg.tagname = tg.tag
        GROUP BY up.user_id, tg.tagname
    )

/* ---------------------------------------------------------------------- */
/*  Main result set – user impact scores                                   */
/* ---------------------------------------------------------------------- */
SELECT
    u.id                                            AS user_id,
    COALESCE(u.displayname, 'Anonymous')            AS display_name,
    COALESCE(up.q_cnt,0)                            AS questions_asked,
    COALESCE(up.a_cnt,0)                            AS answers_given,
    COALESCE(up.a_score_avg,0)                      AS avg_answer_score,
    COALESCE(uv.net_vote,0)                         AS net_vote_score,
    COALESCE(ub.badge_pts,0)                        AS badge_points,
    COALESCE(rc.cmnt_cnt,0)                         AS comment_count,
    /* composite impact metric */
    ( COALESCE(up.a_cnt,0)*2
      + COALESCE(up.q_cnt,0)
      + COALESCE(uv.net_vote,0)*0.5
      + COALESCE(ub.badge_pts,0)*0.1 )             AS impact_score,
    STRING_AGG(DISTINCT tt.tagname, ',')
        FILTER (WHERE tt.rn <= 3)                  AS top_3_tags,
    RANK() OVER (ORDER BY
        ( COALESCE(up.a_cnt,0)*2
          + COALESCE(up.q_cnt,0)
          + COALESCE(uv.net_vote,0)*0.5
          + COALESCE(ub.badge_pts,0)*0.1 ) DESC)   AS impact_rank,
    CASE
        WHEN u.reputation > 20000 THEN 'Legend'
        WHEN u.reputation > 10000 THEN 'Elite'
        WHEN u.reputation > 5000  THEN 'Pro'
        ELSE 'Member'
    END                                             AS reputation_tier,
    ub.named_badges,
    ub.tag_badges,
    ub.last_badge_dt,
    rc.last_cmnt_dt
FROM users u
LEFT JOIN user_posts      up ON up.user_id      = u.id
LEFT JOIN user_badges     ub ON ub.user_id      = u.id
LEFT JOIN user_votes      uv ON uv.user_id      = u.id
LEFT JOIN recent_comments rc ON rc.user_id      = u.id
LEFT JOIN top_tags_per_user tt ON tt.user_id   = u.id AND tt.rn <= 3
WHERE u.creationdate < CURRENT_DATE - INTERVAL '1 year'
GROUP BY
    u.id, u.displayname, u.reputation,
    up.q_cnt, up.a_cnt, up.a_score_avg,
    uv.net_vote,
    ub.badge_pts, ub.named_badges, ub.tag_badges, ub.last_badge_dt,
    rc.cmnt_cnt, rc.last_cmnt_dt
ORDER BY impact_score DESC
LIMIT 10

UNION ALL

/* ---------------------------------------------------------------------- */
/*  Separator row (visual cue)                                            */
/* ---------------------------------------------------------------------- */
SELECT
    NULL, '--- Tag Summary ---', NULL,NULL,NULL,NULL,NULL,NULL,NULL,
    NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
FROM (SELECT 1) AS dummy

UNION ALL

/* ---------------------------------------------------------------------- */
/*  Top‑5 tags overall                                                    */
/* ---------------------------------------------------------------------- */
SELECT
    NULL,
    ts.tag_name,
    ts.tag_post_cnt,
    NULL,
    ts.tag_score,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    ts.contributors,
    NULL,
    NULL
FROM tag_stats ts
ORDER BY ts.tag_post_cnt DESC
LIMIT 5;
