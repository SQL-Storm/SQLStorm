-- {"query": "3751.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2073}
WITH RecentAnswers AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn,
        LAG(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_date,
        CAST(EXTRACT(EPOCH FROM (p.CreationDate - LAG(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate))) / 86400 AS INTEGER) AS days_since_prev
    FROM Posts p
    WHERE p.PostTypeId = 2
      AND p.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '180 days')
),
UserAnswerStats AS (
    SELECT
        u.Id                              AS user_id,
        u.DisplayName,
        COUNT(a.Id)                       AS total_answers,
        AVG(a.Score) FILTER (WHERE a.Score IS NOT NULL) AS avg_score,
        SUM(CASE WHEN a.Score >= 10 THEN 1 ELSE 0 END) AS high_score_answers,
        MAX(a.CreationDate)               AS last_answer_date
    FROM Users u
    LEFT JOIN Posts a
        ON a.OwnerUserId = u.Id
       AND a.PostTypeId = 2
    GROUP BY u.Id, u.DisplayName
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(*)                                 AS total_badges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END)  AS gold_badges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END)  AS silver_badges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END)  AS bronze_badges
    FROM Badges b
    GROUP BY b.UserId
),
UserCloseVotes AS (
    SELECT
        ph.UserId,
        COUNT(*) AS close_votes_cast
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.UserId
),
TopTaggedQuestions AS (
    SELECT
        p.Id,
        p.Title,
        UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags)-2)), '><')) AS tag,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.Score DESC) AS tag_rank
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
),
TagPopularity AS (
    SELECT
        t.TagName,
        t.Count,
        COALESCE(SUM(CASE WHEN tq.tag_rank = 1 THEN 1 ELSE 0 END),0) AS top_questions
    FROM Tags t
    LEFT JOIN TopTaggedQuestions tq
        ON tq.tag = t.TagName
    GROUP BY t.TagName, t.Count
)
SELECT
    uas.user_id,
    uas.DisplayName,
    uas.total_answers,
    CAST(ROUND(uas.avg_score::numeric,2) AS numeric) AS avg_score,
    uas.high_score_answers,
    COALESCE(ubs.total_badges,0)         AS total_badges,
    COALESCE(ubs.gold_badges,0)          AS gold_badges,
    COALESCE(ubs.silver_badges,0)        AS silver_badges,
    COALESCE(ubs.bronze_badges,0)        AS bronze_badges,
    COALESCE(ucv.close_votes_cast,0)    AS close_votes_cast,
    CASE
        WHEN uas.avg_score >= 15 THEN 'Power Answerer'
        WHEN uas.total_answers >= 100 THEN 'Prolific Answerer'
        ELSE 'Active User'
    END                                 AS tier,
    ra.Id                                AS recent_answer_id,
    ra.CreationDate                      AS recent_answer_date,
    ra.prev_date                         AS previous_answer_date,
    ra.days_since_prev                   AS days_since_previous_answer
FROM UserAnswerStats uas
LEFT JOIN UserBadgeStats ubs      ON ubs.UserId = uas.user_id
LEFT JOIN UserCloseVotes ucv      ON ucv.UserId = uas.user_id
LEFT JOIN RecentAnswers ra       ON ra.OwnerUserId = uas.user_id AND ra.rn = 1
WHERE uas.total_answers > 0
  AND (ubs.total_badges IS NULL OR ubs.total_badges < 50)

UNION ALL

SELECT
    u.Id AS user_id,
    u.DisplayName,
    0 AS total_answers,
    CAST(NULL AS numeric) AS avg_score,
    0 AS high_score_answers,
    0 AS total_badges,
    0 AS gold_badges,
    0 AS silver_badges,
    0 AS bronze_badges,
    COALESCE(ucv.close_votes_cast,0) AS close_votes_cast,
    'Newbie' AS tier,
    CAST(NULL AS bigint) AS recent_answer_id,
    CAST(NULL AS timestamp) AS recent_answer_date,
    CAST(NULL AS timestamp) AS previous_answer_date,
    CAST(NULL AS integer) AS days_since_previous_answer
FROM Users u
LEFT JOIN UserCloseVotes ucv ON ucv.UserId = u.Id
WHERE NOT EXISTS (
        SELECT 1 FROM Posts p
        WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2
      )
  AND u.Reputation < 1000

ORDER BY avg_score DESC NULLS LAST, total_answers DESC
LIMIT 100;