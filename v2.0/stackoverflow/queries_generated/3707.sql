-- {"query": "3707.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1986} 

/*  Performance‑benchmarking query – combines CTEs, window functions, 
    correlated subqueries, outer joins, set operators and rich expressions   */
WITH 
/*--------------------------------------------------------------
  1. Base user activity: reputation, recent login, total posts,
     total comments, total votes (up‑mod + down‑mod) and badge counts
--------------------------------------------------------------*/
user_activity AS (
    SELECT
        u.Id                         AS user_id,
        u.DisplayName                AS user_name,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COALESCE(p.post_cnt,0)       AS total_posts,
        COALESCE(c.cmt_cnt,0)        AS total_comments,
        COALESCE(v.up_votes,0)       AS up_votes,
        COALESCE(v.down_votes,0)     AS down_votes,
        COALESCE(b.gold_cnt,0)       AS gold_badges,
        COALESCE(b.silver_cnt,0)     AS silver_badges,
        COALESCE(b.bronze_cnt,0)     AS bronze_badges,
        -- rank users by reputation (window function)
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rep_rank
    FROM Users u
    LEFT JOIN (
        SELECT OwnerUserId, COUNT(*) AS post_cnt
        FROM Posts
        WHERE OwnerUserId IS NOT NULL
        GROUP BY OwnerUserId
    ) p  ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS cmt_cnt
        FROM Comments
        WHERE UserId IS NOT NULL
        GROUP BY UserId
    ) c  ON c.UserId = u.Id
    LEFT JOIN (
        SELECT 
            v.UserId,
            SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS up_votes,
            SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS down_votes
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        GROUP BY v.UserId
    ) v ON v.UserId = u.Id
    LEFT JOIN (
        SELECT 
            UserId,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS gold_cnt,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS silver_cnt,
            SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS bronze_cnt
        FROM Badges
        GROUP BY UserId
    ) b ON b.UserId = u.Id
),

/*--------------------------------------------------------------
  2. Tag‑level statistics: number of questions, average score,
     top‑scoring question per tag (using window function)
--------------------------------------------------------------*/
tag_stats AS (
    SELECT
        t.TagName,
        COUNT(*)                                     AS question_cnt,
        AVG(p.Score)                                 AS avg_score,
        MAX(p.Score)                                 AS max_score,
        -- Identify the question with max score per tag
        FIRST_VALUE(p.Id) OVER (
            PARTITION BY t.TagName
            ORDER BY p.Score DESC, p.CreationDate ASC
        )                                            AS top_question_id,
        -- Concatenate the top 3 tags by popularity (string agg)
        STRING_AGG(t.TagName, ', ') 
            OVER (ORDER BY COUNT(*) DESC 
                  ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
                 )                               AS all_tags_concat
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%'
                 AND p.PostTypeId = 1                      -- only questions
    GROUP BY t.TagName
),

/*--------------------------------------------------------------
  3. Recent activity per user (correlated subquery in SELECT)
--------------------------------------------------------------*/
recent_activity AS (
    SELECT
        ua.user_id,
        ua.user_name,
        ua.reputation,
        ua.rep_rank,
        -- days since last post (correlated subquery)
        COALESCE(
            EXTRACT(DAY FROM (CURRENT_TIMESTAMP - (
                SELECT MAX(CreationDate) 
                FROM Posts p 
                WHERE p.OwnerUserId = ua.user_id
            ))), 
            NULL
        )                                            AS days_since_last_post,
        -- latest comment text (if any) via correlated subquery
        (SELECT c.Text 
         FROM Comments c 
         WHERE c.UserId = ua.user_id 
         ORDER BY c.CreationDate DESC 
         LIMIT 1)                                    AS latest_comment_text
    FROM user_activity ua
),

/*--------------------------------------------------------------
  4. Users with no badges (LEFT JOIN + IS NULL) and at least
     5 posts, used later in a UNION ALL
--------------------------------------------------------------*/
users_no_badges AS (
    SELECT
        ua.user_id,
        ua.user_name,
        ua.reputation,
        ua.total_posts
    FROM user_activity ua
    LEFT JOIN Badges b ON b.UserId = ua.user_id
    WHERE b.Id IS NULL
      AND ua.total_posts >= 5
),

/*--------------------------------------------------------------
  5. Users with high reputation and gold badges (for UNION)
--------------------------------------------------------------*/
high_rep_gold AS (
    SELECT
        ua.user_id,
        ua.user_name,
        ua.reputation,
        ua.gold_badges
    FROM user_activity ua
    WHERE ua.reputation > 20000
      AND ua.gold_badges >= 3
)

/*=============================================================
  Final result set – combines two branches via UNION ALL,
  adds computed columns, applies complex predicates,
  uses CASE, COALESCE, NULL handling and ordering.
==============================================================*/
SELECT
    r.user_id,
    r.user_name,
    r.reputation,
    r.rep_rank,
    r.days_since_last_post,
    COALESCE(r.latest_comment_text, '<no recent comment>') AS latest_comment,
    'ActiveUser'                                  AS user_category,
    NULL::VARCHAR                                 AS top_tag,
    NULL::INT                                     AS top_tag_questions
FROM recent_activity r
WHERE r.days_since_last_post IS NOT NULL
  AND r.days_since_last_post <= 30

UNION ALL

SELECT
    u.user_id,
    u.user_name,
    u.reputation,
    NULL                                          AS rep_rank,
    NULL                                          AS days_since_last_post,
    NULL                                          AS latest_comment,
    'BadgeLessProlific'                           AS user_category,
    ts.TagName                                    AS top_tag,
    ts.question_cnt                               AS top_tag_questions
FROM users_no_badges u
LEFT JOIN (
    SELECT 
        t.TagName,
        COUNT(*) AS question_cnt,
        ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS tag_rank
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%'
                 AND p.PostTypeId = 1
    GROUP BY t.TagName
) ts ON ts.tag_rank = 1
WHERE u.reputation > 5000

UNION ALL

SELECT
    h.user_id,
    h.user_name,
    h.reputation,
    NULL                                          AS rep_rank,
    NULL                                          AS days_since_last_post,
    NULL                                          AS latest_comment,
    'HighRepGold'                                 AS user_category,
    tg.TagName                                    AS top_tag,
    tg.question_cnt                               AS top_tag_questions
FROM high_rep_gold h
JOIN LATERAL (
    SELECT 
        t.TagName,
        COUNT(*) AS question_cnt,
        ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS tag_rank
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%'
                 AND p.PostTypeId = 1
    GROUP BY t.TagName
    ORDER BY question_cnt DESC
    LIMIT 1
) tg ON TRUE
ORDER BY 
    CASE user_category 
        WHEN 'ActiveUser'       THEN 1
        WHEN 'HighRepGold'      THEN 2
        WHEN 'BadgeLessProlific' THEN 3 
    END,
    reputation DESC NULLS LAST;
