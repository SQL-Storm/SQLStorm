-- {"query": "3466.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3006} 

WITH
    user_badge_counts AS (
        SELECT b.UserId,
               SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
               SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
               SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges,
               COUNT(*)                                          AS total_badges
        FROM Badges b
        GROUP BY b.UserId
    ),
    user_vote_sums AS (
        SELECT v.UserId,
               SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS upvote_given,
               SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS downvote_given
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        GROUP BY v.UserId
    ),
    user_post_metrics AS (
        SELECT 
            p.OwnerUserId                                             AS UserId,
            COUNT(*) FILTER (WHERE p.PostTypeId = 1)                  AS question_count,
            COUNT(*) FILTER (WHERE p.PostTypeId = 2)                  AS answer_count,
            COUNT(*) FILTER (WHERE p.Score < 0)                      AS negative_score_posts,
            COUNT(*) FILTER (WHERE p.AcceptedAnswerId IS NOT NULL)   AS questions_with_accepted,
            AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END)         AS avg_answer_score,
            MAX(p.CreationDate)                                      AS last_post_date,
            STRING_AGG(DISTINCT TRIM(BOTH '<>' FROM regexp_replace(p.Tags, '[><]', '', 'g')), ',')
                                                                   AS distinct_tags_used
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),
    recent_activity AS (
        SELECT 
            u.Id,
            MAX(p.CreationDate) AS most_recent_post,
            MAX(c.CreationDate) AS most_recent_comment
        FROM Users u
        LEFT JOIN Posts    p ON p.OwnerUserId = u.Id
        LEFT JOIN Comments c ON c.UserId      = u.Id
        GROUP BY u.Id
    ),
    ranked_users AS (
        SELECT 
            u.Id                                                  AS UserId,
            u.DisplayName,
            u.Reputation,
            COALESCE(ubc.total_badges,0)                           AS total_badges,
            COALESCE(ubc.gold_badges,0)                            AS gold_badges,
            COALESCE(ubc.silver_badges,0)                          AS silver_badges,
            COALESCE(ubc.bronze_badges,0)                          AS bronze_badges,
            COALESCE(uvs.upvote_given,0)                           AS upvote_given,
            COALESCE(uvs.downvote_given,0)                         AS downvote_given,
            COALESCE(upm.question_count,0)                         AS question_count,
            COALESCE(upm.answer_count,0)                           AS answer_count,
            COALESCE(upm.negative_score_posts,0)                   AS negative_score_posts,
            COALESCE(upm.questions_with_accepted,0)                AS questions_with_accepted,
            COALESCE(upm.avg_answer_score,0)                       AS avg_answer_score,
            COALESCE(upm.distinct_tags_used,'')                    AS distinct_tags_used,
            GREATEST(
                COALESCE(ra.most_recent_post,'1970-01-01'::timestamp),
                COALESCE(ra.most_recent_comment,'1970-01-01'::timestamp)
            )                                                      AS last_activity,
            ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, total_badges DESC) AS reputation_rank,
            PERCENT_RANK() OVER (ORDER BY u.Reputation)                                 AS reputation_percentile
        FROM Users u
        LEFT JOIN user_badge_counts  ubc ON ubc.UserId = u.Id
        LEFT JOIN user_vote_sums    uvs ON uvs.UserId = u.Id
        LEFT JOIN user_post_metrics upm ON upm.UserId = u.Id
        LEFT JOIN recent_activity    ra  ON ra.Id     = u.Id
    )
SELECT 
    r.UserId,
    r.DisplayName,
    r.Reputation,
    r.total_badges,
    r.gold_badges,
    r.silver_badges,
    r.bronze_badges,
    r.upvote_given,
    r.downvote_given,
    r.question_count,
    r.answer_count,
    r.negative_score_posts,
    r.questions_with_accepted,
    ROUND(r.avg_answer_score::numeric,2)              AS avg_answer_score,
    r.distinct_tags_used,
    r.last_activity,
    r.reputation_rank,
    r.reputation_percentile,
    CASE 
        WHEN r.reputation_rank <= 10          THEN 'Top 10'
        WHEN r.reputation_percentile >= 0.9   THEN 'Top 10%'
        ELSE                                      'Other'
    END                                               AS tier
FROM ranked_users r
WHERE r.Reputation > 1000
   OR r.total_badges > 5
   OR r.question_count > 20
ORDER BY r.reputation_rank
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY

UNION ALL

SELECT 
    NULL                           AS UserId,
    '--- Summary Row ---'          AS DisplayName,
    NULL                           AS Reputation,
    SUM(r.total_badges)            AS total_badges,
    SUM(r.gold_badges)             AS gold_badges,
    SUM(r.silver_badges)           AS silver_badges,
    SUM(r.bronze_badges)           AS bronze_badges,
    SUM(r.upvote_given)            AS upvote_given,
    SUM(r.downvote_given)          AS downvote_given,
    SUM(r.question_count)          AS question_count,
    SUM(r.answer_count)            AS answer_count,
    SUM(r.negative_score_posts)    AS negative_score_posts,
    SUM(r.questions_with_accepted) AS questions_with_accepted,
    AVG(r.avg_answer_score)        AS avg_answer_score,
    NULL                           AS distinct_tags_used,
    MAX(r.last_activity)           AS last_activity,
    NULL                           AS reputation_rank,
    NULL                           AS reputation_percentile,
    'Summary'                      AS tier
FROM ranked_users r
WHERE r.Reputation > 1000
   OR r.total_badges > 5
   OR r.question_count > 20;
