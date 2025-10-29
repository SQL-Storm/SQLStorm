-- {"query": "3343.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2159} 

/*  Comprehensive benchmark query using CTEs, window functions, outer joins,
    correlated subqueries, string manipulation, NULL logic and a UNION.   */
WITH question_closures AS (
    SELECT
        ph.PostId,
        ph.CreationDate                AS closed_date,
        CAST(ph.Comment AS smallint)   AS close_reason_id          -- comment stores the CloseReasonId
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10                         -- Post Closed
      AND ph.Comment IS NOT NULL
),
answer_stats AS (
    SELECT
        a.Id                               AS answer_id,
        a.ParentId                         AS question_id,
        a.OwnerUserId,
        a.Score                            AS answer_score,
        a.CreationDate,
        COALESCE( (SELECT COUNT(*) FROM Votes v WHERE v.PostId = a.Id AND v.VoteTypeId = 2), 0) AS up_votes,
        COALESCE( (SELECT COUNT(*) FROM Votes v WHERE v.PostId = a.Id AND v.VoteTypeId = 3), 0) AS down_votes
    FROM Posts a
    WHERE a.PostTypeId = 2                                   -- Answer
      AND a.OwnerUserId IS NOT NULL
),
user_aggregation AS (
    SELECT
        u.Id                                   AS user_id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT a.question_id)          AS distinct_q_answered,
        SUM(a.answer_score)                    AS total_answer_score,
        SUM(a.up_votes)                        AS total_up_votes,
        SUM(a.down_votes)                      AS total_down_votes,
        MAX(CASE WHEN qc.close_reason_id = 101 THEN a.CreationDate END) AS last_dup_closed_answer_dt
    FROM Users u
    LEFT JOIN answer_stats a   ON a.OwnerUserId = u.Id
    LEFT JOIN question_closures qc ON qc.PostId = a.question_id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
ranked_users AS (
    SELECT
        ua.*,
        ROW_NUMBER() OVER (ORDER BY ua.total_answer_score DESC, ua.Reputation DESC) AS rank_by_score,
        PERCENT_RANK() OVER (ORDER BY ua.distinct_q_answered)                           AS pct_answered
    FROM user_aggregation ua
    WHERE ua.distinct_q_answered > 10
)
SELECT
    ru.rank_by_score,
    ru.user_id,
    ru.DisplayName,
    ru.Reputation,
    ru.total_answer_score,
    ru.total_up_votes,
    ru.total_down_votes,
    ru.distinct_q_answered,
    COALESCE(b.Name, 'No Badge')                               AS top_badge_name,
    CASE
        WHEN ru.last_dup_closed_answer_dt IS NOT NULL THEN 'ClosedDup'
        ELSE 'Open'
    END                                                       AS recent_close_status,
    CONCAT('Score/', ru.total_answer_score, '|Rep/', ru.Reputation) AS score_rep_tag,
    ru.pct_answered
FROM ranked_users ru
LEFT JOIN LATERAL (
    SELECT b.Name
    FROM Badges b
    WHERE b.UserId = ru.user_id
    ORDER BY b.Class ASC, b.Date DESC
    LIMIT 1
) b ON TRUE
WHERE ru.rank_by_score <= 100

UNION ALL

SELECT
    NULL::int                     AS rank_by_score,
    NULL::int                     AS user_id,
    NULL::varchar                 AS DisplayName,
    NULL::int                     AS Reputation,
    NULL::int                     AS total_answer_score,
    NULL::int                     AS total_up_votes,
    NULL::int                     AS total_down_votes,
    NULL::int                     AS distinct_q_answered,
    '---'::varchar                AS top_badge_name,
    'Summary'::varchar            AS recent_close_status,
    CONCAT('Total Users: ', (SELECT COUNT(*) FROM ranked_users)) AS score_rep_tag,
    (SELECT AVG(total_answer_score) FROM ranked_users)          AS pct_answered
FROM (SELECT 1) s
ORDER BY rank_by_score NULLS LAST;
