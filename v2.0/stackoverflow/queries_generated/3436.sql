-- {"query": "3436.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1479} 

/* 1️⃣ CTE: per‑user activity snapshot */
WITH user_activity AS (
    SELECT
        u.Id                         AS user_id,
        u.DisplayName                AS user_name,
        u.Reputation                 AS reputation,
        COALESCE(u.UpVotes,0)        - COALESCE(u.DownVotes,0) AS net_votes,
        COUNT(p.Id)                  FILTER (WHERE p.PostTypeId = 1) AS question_cnt,
        COUNT(p.Id)                  FILTER (WHERE p.PostTypeId = 2) AS answer_cnt,
        SUM(COALESCE(p.Score,0))     FILTER (WHERE p.PostTypeId = 1) AS question_score,
        SUM(COALESCE(p.Score,0))     FILTER (WHERE p.PostTypeId = 2) AS answer_score,
        COUNT(b.Id)                  AS badge_cnt,
        MAX(p.CreationDate)          AS last_post_date,
        MAX(v.CreationDate)          AS last_vote_date,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Id) AS reputation_rank
    FROM Users u
    LEFT JOIN Posts p          ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b         ON b.UserId = u.Id
    LEFT JOIN Votes v          ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
),

/* 2️⃣ CTE: per‑tag performance derived from question posts */
tag_performance AS (
    SELECT
        t.Id                                 AS tag_id,
        t.TagName                            AS tag_name,
        COUNT(p.Id)                          AS question_cnt,
        SUM(COALESCE(p.Score,0))             AS total_score,
        AVG(COALESCE(p.Score,0))             AS avg_score,
        SUM(COALESCE(p.ViewCount,0))         AS total_views,
        MAX(p.CreationDate)                 AS latest_question_date,
        COUNT(DISTINCT p.OwnerUserId)        AS distinct_authors,
        ROW_NUMBER() OVER (ORDER BY COUNT(p.Id) DESC) AS popularity_rank
    FROM Tags t
    LEFT JOIN LATERAL (
        SELECT *
        FROM Posts p
        WHERE p.PostTypeId = 1                                   -- only questions
          AND p.Tags IS NOT NULL
          AND POSITION(CONCAT('<', t.TagName, '>') IN p.Tags) > 0
    ) p ON TRUE
    GROUP BY t.Id, t.TagName
),

/* 3️⃣ CTE: recent close‑reason activity using correlated sub‑query */
recent_closures AS (
    SELECT
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS closed_at,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS reopened_at,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END)       AS close_reason_code
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (10,11)   -- Close / Reopen events
    GROUP BY ph.PostId
),

/* 4️⃣ CTE: union of badge‑heavy users and high‑scoring answerers */
high_achievers AS (
    SELECT user_id, user_name, reputation, badge_cnt, answer_score
    FROM user_activity
    WHERE badge_cnt >= 50
    UNION ALL
    SELECT user_id, user_name, reputation, badge_cnt, answer_score
    FROM user_activity
    WHERE answer_score >= 1000
)

/* 🎯 Final SELECT – mixing everything together */
SELECT
    ua.user_id,
    ua.user_name,
    ua.reputation,
    ua.net_votes,
    ua.question_cnt,
    ua.answer_cnt,
    ua.question_score,
    ua.answer_score,
    ua.badge_cnt,
    ua.reputation_rank,
    tp.tag_name,
    tp.question_cnt      AS tag_question_cnt,
    tp.avg_score         AS tag_avg_score,
    tp.total_views       AS tag_total_views,
    tp.popularity_rank,
    ph.closed_at,
    ph.reopened_at,
    COALESCE(crt.Name, 'Unknown') AS close_reason_text,
    CASE
        WHEN ph.closed_at IS NOT NULL AND ph.reopened_at IS NULL THEN 'Closed'
        WHEN ph.closed_at IS NOT NULL AND ph.reopened_at IS NOT NULL THEN 'Reopened'
        ELSE 'Open'
    END AS current_status,
    ha.badge_cnt        AS high_achiever_badges,
    ha.answer_score     AS high_achiever_answer_score
FROM user_activity ua
LEFT JOIN recent_closures ph       ON ph.PostId = (
        SELECT p.Id
        FROM Posts p
        WHERE p.OwnerUserId = ua.user_id
          AND p.PostTypeId = 1                 -- only consider questions
        ORDER BY p.CreationDate DESC
        LIMIT 1
    )
LEFT JOIN PostHistoryTypes crt   ON crt.Id = ph.close_reason_code::smallint
LEFT JOIN (
    SELECT
        ua_inner.user_id,
        MIN(tp_inner.tag_name) FILTER (WHERE tp_inner.question_cnt > 0) AS tag_name
    FROM user_activity ua_inner
    LEFT JOIN tag_performance tp_inner
          ON EXISTS (
                SELECT 1
                FROM Posts p
                WHERE p.OwnerUserId = ua_inner.user_id
                  AND p.PostTypeId = 1
                  AND p.Tags IS NOT NULL
                  AND POSITION(CONCAT('<', tp_inner.tag_name, '>') IN p.Tags) > 0
          )
    GROUP BY ua_inner.user_id
) tp_map ON tp_map.user_id = ua.user_id
LEFT JOIN tag_performance tp      ON tp.tag_name = tp_map.tag_name
LEFT JOIN high_achievers ha       ON ha.user_id = ua.user_id
ORDER BY ua.reputation_rank
LIMIT 100;
