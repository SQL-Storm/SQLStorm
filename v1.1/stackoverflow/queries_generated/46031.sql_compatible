WITH high_value_users AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id) AS badge_count,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS gold_badges,
        SUM(p.Score) AS total_post_score,
        COUNT(DISTINCT p.Id) AS post_count
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 5000
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 10
),
question_answer_metrics AS (
    SELECT 
        q.Id AS question_id,
        q.OwnerUserId AS question_owner_id,
        q.Title,
        q.Score AS question_score,
        q.ViewCount,
        q.AnswerCount,
        q.CreationDate AS question_date,
        a.Id AS answer_id,
        a.OwnerUserId AS answer_owner_id,
        a.Score AS answer_score,
        a.CreationDate AS answer_date,
        CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END AS is_accepted,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600 AS hours_to_answer
    FROM Posts q
    INNER JOIN Posts a ON q.Id = a.ParentId
    WHERE q.PostTypeId = 1 
        AND a.PostTypeId = 2
        AND q.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '2 years'
        AND q.Score >= 5
),
tag_performance AS (
    SELECT 
        tag_name,
        COUNT(DISTINCT p.Id) AS questions_count,
        AVG(p.Score) AS avg_score,
        AVG(p.ViewCount) AS avg_views,
        AVG(p.AnswerCount) AS avg_answers,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS total_upvotes,
        COUNT(DISTINCT c.Id) AS total_comments
    FROM (
        SELECT p.*, TRIM(t.tag) AS tag_name
        FROM Posts p
        CROSS JOIN LATERAL (
            SELECT regexp_split_to_table(substring(p.Tags, 2, length(p.Tags)-2), '><') AS tag
        ) t
        WHERE p.PostTypeId = 1 
          AND p.Tags IS NOT NULL
          AND p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '18 months'
    ) p
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    GROUP BY tag_name
    HAVING COUNT(DISTINCT p.Id) >= 50
),
user_engagement_timeline AS (
    SELECT 
        u.Id AS user_id,
        DATE_TRUNC('month', p.CreationDate) AS activity_month,
        COUNT(DISTINCT p.Id) AS posts_created,
        COUNT(DISTINCT c.Id) AS comments_made,
        COUNT(DISTINCT v.Id) AS votes_cast,
        AVG(p.Score) AS avg_post_score
    FROM Users u
    INNER JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId AND DATE_TRUNC('month', c.CreationDate) = DATE_TRUNC('month', p.CreationDate)
    LEFT JOIN Votes v ON u.Id = v.UserId AND DATE_TRUNC('month', v.CreationDate) = DATE_TRUNC('month', p.CreationDate)
    WHERE p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '1 year'
    GROUP BY u.Id, DATE_TRUNC('month', p.CreationDate)
),
question_tags AS (
    -- expand question tags into rows to avoid set-returning functions in JOIN conditions
    SELECT q.Id AS question_id, TRIM(t.tag) AS tag_name, q.Tags
    FROM Posts q
    CROSS JOIN LATERAL (
        SELECT regexp_split_to_table(substring(q.Tags, 2, length(q.Tags)-2), '><') AS tag
    ) t
    WHERE q.PostTypeId = 1 AND q.Tags IS NOT NULL
)
SELECT 
    hvu.DisplayName,
    hvu.Reputation,
    hvu.badge_count,
    hvu.gold_badges,
    tp.tag_name,
    tp.avg_score AS tag_avg_score,
    tp.avg_views AS tag_avg_views,
    COUNT(DISTINCT qam.question_id) AS questions_in_tag,
    COUNT(DISTINCT qam.answer_id) AS answers_in_tag,
    AVG(qam.answer_score) AS avg_answer_score,
    AVG(qam.hours_to_answer) AS avg_hours_to_answer,
    SUM(qam.is_accepted) AS accepted_answers,
    AVG(uet.posts_created) AS avg_monthly_posts,
    AVG(uet.comments_made) AS avg_monthly_comments,
    MAX(uet.activity_month) AS last_active_month,
    RANK() OVER (
        PARTITION BY tp.tag_name 
        ORDER BY COUNT(DISTINCT qam.answer_id) DESC, AVG(qam.answer_score) DESC
    ) AS user_rank_in_tag
FROM high_value_users hvu
INNER JOIN question_answer_metrics qam ON hvu.Id = qam.answer_owner_id
INNER JOIN Posts p ON qam.question_id = p.Id
INNER JOIN question_tags qt ON p.Id = qt.question_id
INNER JOIN tag_performance tp ON qt.tag_name = tp.tag_name
LEFT JOIN user_engagement_timeline uet ON hvu.Id = uet.user_id
WHERE qam.answer_score >= 3
    AND tp.questions_count >= 100
GROUP BY 
    hvu.Id, hvu.DisplayName, hvu.Reputation, hvu.badge_count, hvu.gold_badges,
    tp.tag_name, tp.avg_score, tp.avg_views, tp.questions_count
HAVING COUNT(DISTINCT qam.answer_id) >= 5
ORDER BY tp.questions_count DESC, hvu.Reputation DESC, avg_answer_score DESC
LIMIT 500;