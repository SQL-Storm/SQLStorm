-- {"query": "52022.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 696} 
WITH MonthlyTagStats AS (
    SELECT 
        DATE_TRUNC('month', p.CreationDate) AS month,
        UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS tag,
        p.Score,
        p.ViewCount
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
TagAggregates AS (
    SELECT 
        month,
        tag,
        COUNT(*) AS question_count,
        AVG(Score) AS avg_score,
        AVG(ViewCount) AS avg_views,
        SUM(Score) AS total_score
    FROM MonthlyTagStats
    GROUP BY month, tag
),
RankedTags AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (PARTITION BY month ORDER BY total_score DESC) AS rn
    FROM TagAggregates
),
TopTagPerMonth AS (
    SELECT 
        month,
        tag,
        question_count,
        avg_score,
        avg_views,
        total_score
    FROM RankedTags
    WHERE rn = 1
),
MonthlyPostStats AS (
    SELECT 
        DATE_TRUNC('month', p.CreationDate) AS month,
        COUNT(*) AS total_questions,
        AVG(p.Score) AS avg_question_score,
        SUM(p.ViewCount) AS total_views,
        COUNT(DISTINCT p.OwnerUserId) AS distinct_users
    FROM Posts p
    WHERE p.PostTypeId = 1
    GROUP BY DATE_TRUNC('month', p.CreationDate)
),
UserActivity AS (
    SELECT 
        u.Id,
        u.Reputation,
        COUNT(p.Id) AS question_count,
        AVG(p.Score) AS avg_score,
        SUM(p.ViewCount) AS total_views,
        COUNT(b.Id) AS badge_count,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS gold_badges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS silver_badges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS bronze_badges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation
)
SELECT 
    mps.month,
    mps.total_questions,
    mps.avg_question_score,
    mps.total_views,
    mps.distinct_users,
    tt.tag AS top_tag,
    tt.question_count AS top_tag_questions,
    tt.avg_score AS top_tag_avg_score,
    tt.avg_views AS top_tag_avg_views,
    tt.total_score AS top_tag_total_score,
    COUNT(ua.Id) AS users_with_high_activity,
    AVG(ua.Reputation) AS avg_reputation_high_users
FROM MonthlyPostStats mps
JOIN TopTagPerMonth tt ON mps.month = tt.month
LEFT JOIN UserActivity ua ON ua.question_count >= 5 AND ua.badge_count >= 10 AND ua.avg_score >= 10
GROUP BY mps.month, mps.total_questions, mps.avg_question_score, mps.total_views, mps.distinct_users, tt.tag, tt.question_count, tt.avg_score, tt.avg_views, tt.total_score
ORDER BY mps.month DESC
LIMIT 100;