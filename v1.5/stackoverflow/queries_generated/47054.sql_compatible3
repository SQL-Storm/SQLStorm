WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT pt.Id) AS question_count,
        1 AS level
    FROM Tags t
    INNER JOIN Posts pt ON pt.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    WHERE t.Count > 1000
        AND pt.PostTypeId = 1
    GROUP BY t.Id, t.TagName

    UNION ALL

    SELECT 
        t.Id,
        t.TagName,
        th.question_count,
        th.level + 1
    FROM Tags t
    INNER JOIN tag_hierarchy th ON t.Id <> th.Id
    WHERE th.level < 3
),
user_expertise AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        string_agg(DISTINCT substring(p.Tags, 2, position('>' IN p.Tags) - 2), ', ') AS primary_tags,
        COUNT(DISTINCT p.Id) AS answer_count,
        AVG(p.Score) AS avg_answer_score,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS median_score,
        SUM(p.Score) AS total_score,
        COUNT(DISTINCT CASE WHEN p.Score >= 10 THEN p.Id END) AS great_answers,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId = p.Id THEN p.Id END) AS accepted_answers
    FROM Users u
    INNER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 2
        AND p.Score > 0
        AND u.Reputation > 5000
        AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '2 years')
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) >= 50
),
question_complexity AS (
    SELECT 
        q.Id,
        q.Title,
        q.Score AS question_score,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        LENGTH(q.Body) AS body_length,
        COALESCE(array_length(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><'), 1), 0) AS tag_count,
        COUNT(DISTINCT c.Id) AS comment_count,
        AVG(a.Score) AS avg_answer_score,
        MAX(a.Score) AS best_answer_score,
        EXTRACT(EPOCH FROM (MIN(a.CreationDate) - q.CreationDate)) / 3600 AS hours_to_first_answer,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN ph.Id END) AS edit_count,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.UserId END) AS upvote_users,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.UserId END) AS downvote_users
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Comments c ON c.PostId = q.Id
    LEFT JOIN PostHistory ph ON ph.PostId = q.Id
    LEFT JOIN Votes v ON v.PostId = q.Id
    WHERE q.PostTypeId = 1
        AND q.Score >= 5
        AND q.ClosedDate IS NULL
        AND q.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
    GROUP BY q.Id, q.Title, q.Score, q.ViewCount, q.AnswerCount, q.FavoriteCount, q.Body, q.Tags
    HAVING COUNT(DISTINCT a.Id) >= 3
),
badge_analysis AS (
    SELECT 
        b.UserId,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS gold_badges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS silver_badges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS bronze_badges,
        COUNT(DISTINCT CASE WHEN CAST(b.TagBased AS BOOLEAN) = TRUE THEN b.Name END) AS unique_tag_badges,
        STRING_AGG(DISTINCT CASE WHEN b.Class = 1 THEN b.Name END, ', ') AS gold_badge_names
    FROM Badges b
    GROUP BY b.UserId
)
SELECT 
    ue.DisplayName,
    ue.Reputation,
    ue.primary_tags,
    ue.answer_count,
    ROUND(CAST(ue.avg_answer_score AS NUMERIC), 2) AS avg_answer_score,
    ue.median_score,
    ue.total_score,
    ue.great_answers,
    ue.accepted_answers,
    ROUND(100.0 * ue.accepted_answers / NULLIF(ue.answer_count, 0), 2) AS acceptance_rate,
    ba.gold_badges,
    ba.silver_badges,
    ba.bronze_badges,
    ba.unique_tag_badges,
    ba.gold_badge_names,
    COUNT(DISTINCT qc.Id) AS complex_questions_answered,
    AVG(qc.question_score) AS avg_question_difficulty,
    AVG(qc.hours_to_first_answer) AS avg_response_time_hours,
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY qc.ViewCount) AS p90_question_views,
    SUM(qc.ViewCount) AS total_reached_views,
    DENSE_RANK() OVER (ORDER BY ue.total_score DESC) AS score_rank,
    DENSE_RANK() OVER (ORDER BY ue.accepted_answers DESC) AS acceptance_rank,
    DENSE_RANK() OVER (ORDER BY ba.gold_badges DESC, ba.silver_badges DESC) AS badge_rank,
    LAG(ue.total_score, 1) OVER (ORDER BY ue.total_score DESC) - ue.total_score AS score_gap_to_next
FROM user_expertise ue
INNER JOIN badge_analysis ba ON ue.UserId = ba.UserId
INNER JOIN Posts ans ON ans.OwnerUserId = ue.UserId AND ans.PostTypeId = 2
INNER JOIN question_complexity qc ON qc.Id = ans.ParentId
WHERE ba.gold_badges > 0
    OR ue.total_score > 1000
GROUP BY 
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.primary_tags,
    ue.answer_count,
    ue.avg_answer_score,
    ue.median_score,
    ue.total_score,
    ue.great_answers,
    ue.accepted_answers,
    ba.gold_badges,
    ba.silver_badges,
    ba.bronze_badges,
    ba.unique_tag_badges,
    ba.gold_badge_names
ORDER BY ue.total_score DESC
LIMIT 100;