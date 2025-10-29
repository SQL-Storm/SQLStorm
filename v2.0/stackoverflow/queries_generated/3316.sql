-- {"query": "3316.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1637} 

/*  BENCHMARK QUERY – heavy use of CTEs, window functions, outer joins, 
    correlated sub‑queries, set operators and complex expressions            */
WITH
/* ----------------------------------------------------------------------
   1. Aggregate per‑user statistics (post counts, scores, recent activity)
   ---------------------------------------------------------------------- */
user_agg AS (
    SELECT
        u.Id                                   AS user_id,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id)                             AS total_posts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS question_score_sum,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS answer_score_sum,
        MAX(p.CreationDate)                    AS newest_post_date,
        MIN(p.CreationDate)                    AS oldest_post_date,
        COUNT(DISTINCT v.VoteTypeId)           AS distinct_vote_types,
        COALESCE(SUM(v.BountyAmount),0)         AS total_bounty_awarded
    FROM Users u
    LEFT JOIN Posts p          ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v          ON v.PostId = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),

/* ----------------------------------------------------------------------
   2. Badge summary per user (gold/silver/bronze, tag‑based flag)
   ---------------------------------------------------------------------- */
badge_summary AS (
    SELECT
        b.UserId                                   AS user_id,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)  AS gold_cnt,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)  AS silver_cnt,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)  AS bronze_cnt,
        MAX(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END) AS has_tag_badge
    FROM Badges b
    GROUP BY b.UserId
),

/* ----------------------------------------------------------------------
   3. Most recent post title per user (correlated subquery inside CTE)
   ---------------------------------------------------------------------- */
recent_titles AS (
    SELECT
        u.Id                                     AS user_id,
        (SELECT p.Title
         FROM Posts p
         WHERE p.OwnerUserId = u.Id
           AND p.Title IS NOT NULL
         ORDER BY p.CreationDate DESC
         LIMIT 1)                               AS latest_title
    FROM Users u
),

/* ----------------------------------------------------------------------
   4. Top tag used by each user (window function over Tags → Posts)
   ---------------------------------------------------------------------- */
user_top_tag AS (
    SELECT *
    FROM (
        SELECT
            p.OwnerUserId                         AS user_id,
            UNNEST(string_to_array(
                    TRIM(BOTH '<>' FROM COALESCE(p.Tags, '')),
                    '><'))                         AS tag,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId
                               ORDER BY COUNT(*) DESC) AS rn
        FROM Posts p
        WHERE p.PostTypeId = 1                     -- only questions
          AND p.Tags IS NOT NULL
        GROUP BY p.OwnerUserId, tag
    ) t
    WHERE rn = 1
),

/* ----------------------------------------------------------------------
   5. Users with a recent vote of type “UpMod” (set operator to include
      “DownMod” as well, then filter with INTERSECT)
   ---------------------------------------------------------------------- */
recent_up_votes AS (
    SELECT DISTINCT v.UserId
    FROM Votes v
    WHERE v.VoteTypeId = 2                               -- UpMod
      AND v.CreationDate > CURRENT_DATE - INTERVAL '30 days'
),
recent_down_votes AS (
    SELECT DISTINCT v.UserId
    FROM Votes v
    WHERE v.VoteTypeId = 3                               -- DownMod
      AND v.CreationDate > CURRENT_DATE - INTERVAL '30 days'
),
active_voters AS (
    SELECT UserId FROM recent_up_votes
    INTERSECT
    SELECT UserId FROM recent_down_votes
),

/* ----------------------------------------------------------------------
   6. Final assembled result (outer joins, case/NULL logic, string ops)
   ---------------------------------------------------------------------- */
final_set AS (
    SELECT
        ua.user_id,
        ua.DisplayName,
        ua.Reputation,
        ua.total_posts,
        ua.question_score_sum,
        ua.answer_score_sum,
        ua.newest_post_date,
        ua.oldest_post_date,
        ua.distinct_vote_types,
        ua.total_bounty_awarded,
        COALESCE(bs.gold_cnt,0)     AS gold_badges,
        COALESCE(bs.silver_cnt,0)   AS silver_badges,
        COALESCE(bs.bronze_cnt,0)   AS bronze_badges,
        CASE WHEN COALESCE(bs.has_tag_badge,0) = 1 THEN 'YES' ELSE 'NO' END AS has_tag_badge,
        rt.latest_title,
        COALESCE(utt.tag,'<none>')  AS top_tag,
        CASE
            WHEN av.UserId IS NOT NULL THEN 'ACTIVE VOTER'
            ELSE 'PASSIVE'
        END                        AS voter_status,
        /* complex calculated metric */
        ROUND(
            (ua.question_score_sum * 1.5 +
             ua.answer_score_sum * 2.0 +
             ua.total_bounty_awarded * 0.8) /
            NULLIF(ua.total_posts,0), 2
        )                         AS engagement_score,
        /* build a diagnostic string, handling NULLs */
        CONCAT(
            'User#', ua.user_id, ': ',
            COALESCE(ua.DisplayName, 'Anonymous'), ' | ',
            'Rep ', ua.Reputation, ' | ',
            'Posts ', ua.total_posts, ' | ',
            'Gold ', COALESCE(bs.gold_cnt,0), ', ',
            'Silver ', COALESCE(bs.silver_cnt,0), ', ',
            'Bronze ', COALESCE(bs.bronze_cnt,0)
        )                         AS diagnostic_blob
    FROM user_agg ua
    LEFT JOIN badge_summary bs          ON bs.user_id = ua.user_id
    LEFT JOIN recent_titles rt          ON rt.user_id = ua.user_id
    LEFT JOIN user_top_tag utt          ON utt.user_id = ua.user_id
    LEFT JOIN active_voters av          ON av.UserId = ua.user_id
)

SELECT *
FROM final_set
WHERE engagement_score > 0
   AND voter_status = 'ACTIVE VOTER'
ORDER BY engagement_score DESC
LIMIT 100;
