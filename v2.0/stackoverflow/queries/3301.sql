-- {"query": "3301.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2650} 
WITH
    /*  Users that have posted at least 10 items (questions or answers)  */
    user_activity AS (
        SELECT
            u.Id                                 AS user_id,
            u.DisplayName,
            u.Reputation,
            u.Location,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS question_cnt,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS answer_cnt,
            SUM(COALESCE(p.Score,0))               AS total_score,
            SUM(COALESCE(p.ViewCount,0))           AS total_views
        FROM Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
        HAVING COUNT(p.Id) >= 10
    ),

    /*  Most recent question per user (title and date)  */
    recent_q AS (
        SELECT
            p.OwnerUserId,
            p.Title,
            p.CreationDate,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
        FROM Posts p
        WHERE p.PostTypeId = 1
    ),
    recent_question AS (
        SELECT OwnerUserId, Title, CreationDate
        FROM recent_q
        WHERE rn = 1
    ),

    /*  Badge aggregation per user  */
    badge_summary AS (
        SELECT
            b.UserId,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_cnt,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_cnt,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_cnt,
            MAX(b.Date)                                   AS last_badge_date
        FROM Badges b
        GROUP BY b.UserId
    ),

    /*  Vote statistics per user (from his posts)  */
    vote_stats AS (
        SELECT
            p.OwnerUserId                      AS user_id,
            COUNT(v.Id)                        AS vote_cnt,
            SUM(CASE
                    WHEN v.VoteTypeId = 2 THEN  1   /* upvote   */
                    WHEN v.VoteTypeId = 3 THEN -1   /* downvote */
                    ELSE 0
                END)                           AS vote_score
        FROM Posts p
        LEFT JOIN Votes v ON v.PostId = p.Id
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),

    /*  Rank users by reputation and compute cumulative reputation  */
    ranked_users AS (
        SELECT
            ua.user_id,
            ua.DisplayName,
            ua.Reputation,
            ua.question_cnt,
            ua.answer_cnt,
            ua.total_score,
            ua.total_views,
            rq.Title                     AS latest_question_title,
            COALESCE(bs.gold_cnt,0)      AS gold_badges,
            COALESCE(bs.silver_cnt,0)    AS silver_badges,
            COALESCE(bs.bronze_cnt,0)    AS bronze_badges,
            vs.vote_cnt,
            vs.vote_score,
            ROW_NUMBER() OVER (ORDER BY ua.Reputation DESC)                                           AS rep_rank,
            SUM(ua.Reputation) OVER (ORDER BY ua.Reputation DESC
                                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)               AS cum_rep,
            CONCAT(COALESCE(ua.DisplayName,'Anonymous'),' (',ua.user_id,')')                        AS user_label,
            COALESCE(ua.Location,'Unknown')                                                          AS user_location
        FROM user_activity ua
        LEFT JOIN recent_question rq   ON rq.OwnerUserId   = ua.user_id
        LEFT JOIN badge_summary bs    ON bs.UserId       = ua.user_id
        LEFT JOIN vote_stats vs       ON vs.user_id      = ua.user_id
    )

/*  Final result set using set operators, window functions and rich predicates  */
SELECT
    user_id,
    user_label,
    Reputation,
    question_cnt,
    answer_cnt,
    total_score,
    total_views,
    latest_question_title,
    gold_badges,
    silver_badges,
    bronze_badges,
    vote_cnt,
    vote_score,
    rep_rank,
    cum_rep,
    user_location
FROM ranked_users
WHERE gold_badges > 0                                 -- users with at least one gold badge
UNION ALL
SELECT
    user_id,
    user_label,
    Reputation,
    question_cnt,
    answer_cnt,
    total_score,
    total_views,
    latest_question_title,
    gold_badges,
    silver_badges,
    bronze_badges,
    vote_cnt,
    vote_score,
    rep_rank,
    cum_rep,
    user_location
FROM ranked_users
WHERE gold_badges = 0 AND silver_badges > 0          -- users with silver but no gold
EXCEPT
SELECT
    user_id,
    user_label,
    Reputation,
    question_cnt,
    answer_cnt,
    total_score,
    total_views,
    latest_question_title,
    gold_badges,
    silver_badges,
    bronze_badges,
    vote_cnt,
    vote_score,
    rep_rank,
    cum_rep,
    user_location
FROM ranked_users
WHERE rep_rank > 200;