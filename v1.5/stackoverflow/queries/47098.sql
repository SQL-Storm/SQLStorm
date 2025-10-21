WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT pt.PostId) AS direct_posts,
        1 AS level
    FROM Tags t
    JOIN (
        SELECT p.Id AS PostId,
               UNNEST(string_to_array(SUBSTRING(Tags FROM 2 FOR LENGTH(Tags) - 2), '><')) AS tag
        FROM Posts p
        WHERE p.PostTypeId = 1
          AND p.Tags IS NOT NULL
    ) AS pt ON pt.tag = t.TagName
    WHERE t.Count > 1000
    GROUP BY t.Id, t.TagName
),
user_expertise AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        pt.tag,
        COUNT(DISTINCT p.Id) AS answer_count,
        SUM(p.Score) AS total_score,
        AVG(p.Score) AS avg_score,
        MAX(p.Score) AS max_score,
        COUNT(DISTINCT CASE WHEN p.Id = q.AcceptedAnswerId THEN p.Id END) AS accepted_answers,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY p.Score) AS median_score,
        COUNT(DISTINCT CASE WHEN b.TagBased = TRUE AND b.Name = pt.tag THEN b.Name END) AS tag_badges
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    JOIN Posts q ON q.Id = p.ParentId
    LEFT JOIN Badges b ON b.UserId = u.Id
    CROSS JOIN LATERAL (
        SELECT UNNEST(string_to_array(SUBSTRING(q.Tags FROM 2 FOR LENGTH(q.Tags) - 2), '><')) AS tag
    ) AS pt
    WHERE p.PostTypeId = 2
      AND p.Score > 0
      AND u.Reputation > 5000
      AND q.Tags IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, pt.tag
    HAVING COUNT(DISTINCT p.Id) >= 10
),
temporal_patterns AS (
    SELECT 
        DATE_TRUNC('month', p.CreationDate) AS month,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS questions,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS answers,
        AVG(p.Score) FILTER (WHERE p.Score > 0) AS avg_positive_score,
        STDDEV_SAMP(p.Score) FILTER (WHERE p.Score IS NOT NULL) AS score_stddev,
        COUNT(DISTINCT p.OwnerUserId) AS unique_contributors,
        SUM(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) AS total_views,
        AVG(p.AnswerCount) FILTER (WHERE p.PostTypeId = 1 AND p.AnswerCount > 0) AS avg_answers,
        COUNT(*) FILTER (WHERE p.AcceptedAnswerId IS NOT NULL) AS questions_with_accepted,
        AVG(EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 3600) AS avg_hours_to_last_activity
    FROM Posts p
    WHERE p.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2 years'
      AND p.CreationDate < TIMESTAMP '2024-10-01 12:34:56'
    GROUP BY DATE_TRUNC('month', p.CreationDate)
),
comment_sentiment AS (
    SELECT 
        c.PostId,
        COUNT(*) AS comment_count,
        AVG(c.Score) AS avg_comment_score,
        COUNT(*) FILTER (WHERE c.Text LIKE '%thank%' OR c.Text LIKE '%great%' OR c.Text LIKE '%excellent%') AS positive_signals,
        COUNT(*) FILTER (WHERE c.Text LIKE '%wrong%' OR c.Text LIKE '%bad%' OR c.Text LIKE '%terrible%') AS negative_signals,
        MAX(c.Score) AS max_comment_score,
        COUNT(DISTINCT c.UserId) AS unique_commenters
    FROM Comments c
    WHERE c.CreationDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year'
    GROUP BY c.PostId
)
SELECT 
    ue.DisplayName,
    ue.Reputation,
    ue.tag AS expertise_tag,
    ue.answer_count,
    ue.total_score,
    ue.avg_score,
    ue.median_score,
    ue.accepted_answers,
    ROUND(100.0 * ue.accepted_answers / NULLIF(ue.answer_count, 0), 2) AS acceptance_rate,
    ue.tag_badges,
    th.direct_posts AS tag_usage_count,
    tp.month,
    tp.questions AS monthly_questions,
    tp.answers AS monthly_answers,
    tp.avg_positive_score AS monthly_avg_score,
    tp.score_stddev,
    tp.unique_contributors,
    tp.total_views,
    tp.avg_answers AS avg_answers_per_question,
    ROUND(100.0 * tp.questions_with_accepted / NULLIF(tp.questions, 0), 2) AS monthly_acceptance_rate,
    tp.avg_hours_to_last_activity,
    COALESCE(cs.avg_comment_score, 0) AS related_comment_sentiment,
    COALESCE(cs.positive_signals - cs.negative_signals, 0) AS comment_sentiment_differential,
    RANK() OVER (PARTITION BY ue.tag ORDER BY ue.total_score DESC) AS tag_rank,
    DENSE_RANK() OVER (PARTITION BY tp.month ORDER BY ue.total_score DESC) AS monthly_rank,
    LAG(tp.questions, 1) OVER (PARTITION BY ue.tag ORDER BY tp.month) AS prev_month_questions,
    LEAD(tp.answers, 1) OVER (PARTITION BY ue.tag ORDER BY tp.month) AS next_month_answers,
    SUM(ue.total_score) OVER (PARTITION BY ue.UserId ORDER BY tp.month ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_score,
    NTILE(10) OVER (ORDER BY ue.Reputation DESC) AS reputation_decile
FROM user_expertise ue
CROSS JOIN temporal_patterns tp
JOIN tag_hierarchy th ON th.TagName = ue.tag
LEFT JOIN LATERAL (
    SELECT cs.*
    FROM Posts p
    JOIN comment_sentiment cs ON cs.PostId = p.Id
    WHERE p.OwnerUserId = ue.UserId
    LIMIT 1
) AS cs ON TRUE
WHERE ue.avg_score > 5
  AND th.direct_posts > 100
ORDER BY ue.total_score DESC, tp.month DESC
LIMIT 1000;