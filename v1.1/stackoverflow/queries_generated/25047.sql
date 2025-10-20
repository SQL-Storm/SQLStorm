-- {"query": "25047.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3028} 

/*  Elaborate benchmark query – uses CTEs, window functions, outer joins,
    correlated subqueries, set operators, string ops and NULL logic   */
WITH
    /* per‑user post aggregates */
    usr_posts AS (
        SELECT
            u.Id                                     AS user_id,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS ques_cnt,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS ans_cnt,
            SUM(p.Score) FILTER (WHERE p.PostTypeId = 1) AS ques_score_sum,
            SUM(p.Score) FILTER (WHERE p.PostTypeId = 2) AS ans_score_sum,
            MAX(p.CreationDate)                     AS last_post_dt
        FROM Users u
        LEFT JOIN Posts p
               ON p.OwnerUserId = u.Id
        GROUP BY u.Id
    ),

    /* per‑user badge aggregates */
    usr_badges AS (
        SELECT
            b.UserId                                 AS user_id,
            COUNT(*) FILTER (WHERE b.Class = 1)      AS gold_cnt,
            COUNT(*) FILTER (WHERE b.Class = 2)      AS silver_cnt,
            COUNT(*) FILTER (WHERE b.Class = 3)      AS bronze_cnt,
            MAX(b.Date)                              AS last_badge_dt
        FROM Badges b
        GROUP BY b.UserId
    ),

    /* per‑user tag usage with ranking – uses LATERAL split of Tags */
    usr_tag_usage AS (
        SELECT
            p.OwnerUserId                            AS user_id,
            t.tag_name,
            COUNT(*)                                 AS tag_used,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId
                               ORDER BY COUNT(*) DESC) AS tag_rank
        FROM Posts p
        CROSS JOIN LATERAL (
            SELECT unnest(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS tag_name
        ) t
        WHERE p.PostTypeId = 1                -- only questions have tags
        GROUP BY p.OwnerUserId, t.tag_name
    ),

    /* most recent vote per post in the last 30 days */
    recent_votes AS (
        SELECT
            v.PostId,
            v.VoteTypeId,
            v.UserId,
            v.CreationDate,
            ROW_NUMBER() OVER (PARTITION BY v.PostId
                               ORDER BY v.CreationDate DESC) AS rn
        FROM Votes v
        WHERE v.CreationDate > now() - interval '30 day'
    ),

    /* comment count per user (may be NULL) */
    usr_comments AS (
        SELECT
            c.UserId                                 AS user_id,
            COUNT(*)                                 AS comm_cnt
        FROM Comments c
        GROUP BY c.UserId
    )

/* ------------------------------------------------------------------ */
/* Main result set – one row per user (limited to top 100 by rep)     */
SELECT
    u.Id                                              AS user_id,
    u.DisplayName                                     AS display_name,
    COALESCE(up.ques_cnt, 0)                           AS question_count,
    COALESCE(up.ans_cnt, 0)                            AS answer_count,
    COALESCE(up.ques_score_sum, 0) /
        NULLIF(COALESCE(up.ques_cnt, 0), 0)            AS avg_question_score,
    COALESCE(up.ans_score_sum, 0) /
        NULLIF(COALESCE(up.ans_cnt, 0), 0)             AS avg_answer_score,
    COALESCE(ub.gold_cnt, 0)                           AS gold_badges,
    COALESCE(ub.silver_cnt, 0)                         AS silver_badges,
    COALESCE(ub.bronze_cnt, 0)                         AS bronze_badges,
    CASE
        WHEN ub.last_badge_dt IS NULL THEN 'Never'
        ELSE to_char(ub.last_badge_dt, 'YYYY-MM-DD')
    END                                                AS last_badge_date,
    (SELECT string_agg(tu.tag_name, ', ')
       FROM usr_tag_usage tu
      WHERE tu.user_id = u.Id AND tu.tag_rank <= 3)   AS top_3_tags,
    EXISTS (SELECT 1
              FROM recent_votes rv
              JOIN Posts rp ON rp.Id = rv.PostId
             WHERE rv.rn = 1 AND rp.OwnerUserId = u.Id) AS has_recent_vote,
    CASE
        WHEN u.Reputation > 20000 THEN 'Legendary'
        WHEN u.Reputation > 10000 THEN 'Expert'
        WHEN u.Reputation > 2000  THEN 'Contributor'
        ELSE 'Newbie'
    END                                                AS reputation_tier,
    COALESCE(uc.comm_cnt, 0)                           AS comment_count
FROM Users u
LEFT JOIN usr_posts   up ON up.user_id   = u.Id
LEFT JOIN usr_badges  ub ON ub.user_id   = u.Id
LEFT JOIN usr_comments uc ON uc.user_id = u.Id
WHERE (u.CreationDate < now() - interval '1 year' OR u.Reputation > 0)
ORDER BY u.Reputation DESC
LIMIT 100

/* ------------------------------------------------------------------ */
/* Summary row – aggregates across the whole data set (unioned)       */
UNION ALL
SELECT
    0                                               AS user_id,
    'TOTAL'                                         AS display_name,
    SUM(COALESCE(up.ques_cnt,0))                    AS question_count,
    SUM(COALESCE(up.ans_cnt,0))                     AS answer_count,
    NULL                                            AS avg_question_score,
    NULL                                            AS avg_answer_score,
    SUM(COALESCE(ub.gold_cnt,0))                    AS gold_badges,
    SUM(COALESCE(ub.silver_cnt,0))                  AS silver_badges,
    SUM(COALESCE(ub.bronze_cnt,0))                  AS bronze_badges,
    NULL                                            AS last_badge_date,
    NULL                                            AS top_3_tags,
    NULL                                            AS has_recent_vote,
    NULL                                            AS reputation_tier,
    (SELECT COUNT(*) FROM Comments)                AS comment_count
FROM Users u
LEFT JOIN usr_posts   up ON up.user_id   = u.Id
LEFT JOIN usr_badges  ub ON ub.user_id   = u.Id;
