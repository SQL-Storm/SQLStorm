-- {"query": "39073.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 2348} 
WITH question_tags AS (
    SELECT
        p.Id AS question_id,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS tag
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
),
tag_metrics AS (
    SELECT
        qt.tag,
        COUNT(*)            AS question_count,
        AVG(q.Score)        AS avg_score,
        SUM(q.ViewCount)    AS total_views
    FROM question_tags qt
    JOIN Posts q
      ON q.Id = qt.question_id
    GROUP BY qt.tag
),
top_tags AS (
    SELECT
        tag
    FROM tag_metrics
    ORDER BY question_count DESC
    LIMIT 5
),
user_activity AS (
    SELECT
        u.Id                                 AS user_id,
        u.DisplayName,
        COUNT(DISTINCT p.Id)                 AS post_count,
        COUNT(com.Id)                        AS comment_count,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes_received,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes_received,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC)    AS user_rank
    FROM Users u
    LEFT JOIN Posts    p  ON p.OwnerUserId = u.Id
    LEFT JOIN Comments com ON com.UserId      = u.Id
    LEFT JOIN Votes    v  ON v.UserId         = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(p.Id) > 10
),
tag_top_answerers AS (
    SELECT
        tt.tag,
        ua.DisplayName     AS top_answerer,
        COUNT(a.Id)        AS answer_count,
        ROW_NUMBER() OVER (PARTITION BY tt.tag ORDER BY COUNT(a.Id) DESC) AS rn
    FROM top_tags tt
    JOIN question_tags qt
      ON qt.tag = tt.tag
    JOIN Posts a
      ON a.ParentId = qt.question_id
     AND a.PostTypeId = 2
    JOIN user_activity ua
      ON ua.user_id = a.OwnerUserId
    GROUP BY tt.tag, ua.DisplayName
)
SELECT
    tm.tag,
    tm.question_count,
    ROUND(tm.avg_score, 2)     AS avg_question_score,
    tm.total_views,
    tta.top_answerer,
    tta.answer_count,
    ua.upvotes_received,
    ua.comment_count,
    ua.user_rank
FROM tag_metrics tm
JOIN tag_top_answerers tta
  ON tta.tag = tm.tag
 AND tta.rn = 1
JOIN user_activity ua
  ON ua.DisplayName = tta.top_answerer
WHERE tm.tag IN (SELECT tag FROM top_tags)
ORDER BY tm.question_count DESC, ua.user_rank;