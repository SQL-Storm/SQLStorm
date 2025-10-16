-- {"query": "25075.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2541} 

/*  Benchmark query combining CTEs, outer joins, correlated subqueries, window functions,
    set operators, complex predicates, string handling and NULL logic. */
WITH
    -- Base user activity aggregation
    user_stats AS (
        SELECT
            u.Id                                 AS user_id,
            u.DisplayName,
            u.Reputation,
            u.CreationDate,
            u.LastAccessDate,
            COUNT(p.Id)                           AS total_posts,
            SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS question_cnt,
            SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS answer_cnt,
            AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS avg_score,
            MAX(p.CreationDate)                  AS last_post_date,
            STRING_AGG(DISTINCT TRIM(BOTH '<' FROM REPLACE(p.Tags, '><', ',')), ', ') 
                                                FILTER (WHERE p.Tags IS NOT NULL) AS tag_list
        FROM Users u
        LEFT JOIN Posts p
               ON p.OwnerUserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
    ),

    -- Badge summarisation per user
    badge_stats AS (
        SELECT
            b.UserId               AS user_id,
            COUNT(*)               AS badge_total,
            COUNT(*) FILTER (WHERE b.Class = 1) AS gold_cnt,
            COUNT(*) FILTER (WHERE b.Class = 2) AS silver_cnt,
            COUNT(*) FILTER (WHERE b.Class = 3) AS bronze_cnt,
            STRING_AGG(DISTINCT b.Name, ', ')   AS badge_names
        FROM Badges b
        GROUP BY b.UserId
    ),

    -- Vote totals per post (windowed summary)
    post_votes AS (
        SELECT
            v.PostId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY v.PostId) AS up_votes,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY v.PostId) AS down_votes
        FROM Votes v
    ),

    -- Net vote score per user (correlated sub‑query)
    user_vote_score AS (
        SELECT
            p.OwnerUserId AS user_id,
            COALESCE(SUM(pv.up_votes - pv.down_votes),0) AS net_vote_score
        FROM Posts p
        LEFT JOIN post_votes pv
               ON pv.PostId = p.Id
        GROUP BY p.OwnerUserId
    ),

    -- Recent activity (outer join with possible NULLs)
    recent_activity AS (
        SELECT
            u.Id                     AS user_id,
            GREATEST(
                u.LastAccessDate,
                COALESCE(MAX(p.LastActivityDate), TIMESTAMP '1970-01-01')
            )                        AS last_activity
        FROM Users u
        LEFT JOIN Posts p
               ON p.OwnerUserId = u.Id
        GROUP BY u.Id, u.LastAccessDate
    ),

    -- Link counts per user via a sub‑query in SELECT list
    user_link_counts AS (
        SELECT
            u.Id AS user_id,
            (
                SELECT COUNT(*)
                FROM PostLinks pl
                WHERE pl.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id)
                   OR pl.RelatedPostId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id)
            ) AS total_links
        FROM Users u
    )

-- Final result set mixing all the above, with UNION ALL to add an aggregate row
SELECT
    us.user_id,
    us.DisplayName,
    us.Reputation,
    us.total_posts,
    us.question_cnt,
    us.answer_cnt,
    ROUND(us.avg_score,2)                     AS avg_score,
    us.last_post_date,
    bs.badge_total,
    bs.gold_cnt,
    bs.silver_cnt,
    bs.bronze_cnt,
    bs.badge_names,
    uv.net_vote_score,
    ra.last_activity,
    ulc.total_links,
    CASE
        WHEN us.Reputation >= 200000 THEN 'Legendary'
        WHEN us.Reputation >= 100000 THEN 'Elite'
        WHEN us.Reputation >= 50000  THEN 'Pro'
        WHEN us.Reputation >= 20000  THEN 'Experienced'
        ELSE 'Regular'
    END                                      AS reputation_tier,
    ROW_NUMBER() OVER (ORDER BY us.Reputation DESC NULLS LAST) AS rank_by_rep,
    /* Complex predicate using string functions and NULL handling */
    CASE
        WHEN us.tag_list IS NULL THEN 'NoTags'
        WHEN POSITION('sql' IN LOWER(us.tag_list)) > 0 THEN 'SQLExpert'
        ELSE 'Other'
    END                                      AS tag_profile
FROM user_stats us
LEFT JOIN badge_stats bs
       ON bs.user_id = us.user_id
LEFT JOIN user_vote_score uv
       ON uv.user_id = us.user_id
LEFT JOIN recent_activity ra
       ON ra.user_id = us.user_id
LEFT JOIN user_link_counts ulc
       ON ulc.user_id = us.user_id
WHERE
    /* Mix of date logic, NULL logic and set operator side‑effects */
    (us.Reputation IS NOT NULL AND us.Reputation > 0)
    AND (us.CreationDate < DATE '2015-01-01' OR us.last_post_date > NOW() - INTERVAL '1 year')
    AND (bs.badge_total IS NULL OR bs.badge_total > 0)
ORDER BY us.Reputation DESC NULLS LAST
LIMIT 100

UNION ALL

/* Aggregate row for quick sanity‑check */
SELECT
    NULL                                    AS user_id,
    'TOTAL'                                 AS DisplayName,
    SUM(us.Reputation)                      AS Reputation,
    SUM(us.total_posts)                     AS total_posts,
    SUM(us.question_cnt)                    AS question_cnt,
    SUM(us.answer_cnt)                      AS answer_cnt,
    ROUND(AVG(us.avg_score),2)              AS avg_score,
    MAX(us.last_post_date)                  AS last_post_date,
    SUM(bs.badge_total)                     AS badge_total,
    SUM(bs.gold_cnt)                        AS gold_cnt,
    SUM(bs.silver_cnt)                      AS silver_cnt,
    SUM(bs.bronze_cnt)                      AS bronze_cnt,
    NULL                                    AS badge_names,
    SUM(uv.net_vote_score)                  AS net_vote_score,
    MAX(ra.last_activity)                  AS last_activity,
    SUM(ulc.total_links)                    AS total_links,
    NULL                                    AS reputation_tier,
    NULL                                    AS rank_by_rep,
    NULL                                    AS tag_profile
FROM user_stats us
LEFT JOIN badge_stats bs   ON bs.user_id = us.user_id
LEFT JOIN user_vote_score uv ON uv.user_id = us.user_id
LEFT JOIN recent_activity ra ON ra.user_id = us.user_id
LEFT JOIN user_link_counts ulc ON ulc.user_id = us.user_id
WHERE
    us.Reputation IS NOT NULL;
