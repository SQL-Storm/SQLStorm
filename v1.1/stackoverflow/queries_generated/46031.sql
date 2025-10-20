-- {"query": "46031.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 71114, "output_tokens": 56935} 

WITH high_value_users AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id) as badge_count,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as gold_badges,
        SUM(p.Score) as total_post_score,
        COUNT(DISTINCT p.Id) as post_count
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 5000
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 10
),
question_answer_metrics AS (
    SELECT 
        q.Id as question_id,
        q.OwnerUserId as question_owner_id,
        q.Title,
        q.Score as question_score,
        q.ViewCount,
        q.AnswerCount,
        q.CreationDate as question_date,
        a.Id as answer_id,
        a.OwnerUserId as answer_owner_id,
        a.Score as answer_score,
        a.CreationDate as answer_date,
        CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END as is_accepted,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600 as hours_to_answer
    FROM Posts q
    INNER JOIN Posts a ON q.Id = a.ParentId
    WHERE q.PostTypeId = 1 
        AND a.PostTypeId = 2
        AND q.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
        AND q.Score >= 5
),
tag_performance AS (
    SELECT 
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as tag_name,
        COUNT(DISTINCT p.Id) as questions_count,
        AVG(p.Score) as avg_score,
        AVG(p.ViewCount) as avg_views,
        AVG(p.AnswerCount) as avg_answers,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) as total_upvotes,
        COUNT(DISTINCT c.Id) as total_comments
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 1 
        AND p.Tags IS NOT NULL
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '18 months'
    GROUP BY tag_name
    HAVING COUNT(DISTINCT p.Id) >= 50
),
user_engagement_timeline AS (
    SELECT 
        u.Id as user_id,
        DATE_TRUNC('month', p.CreationDate) as activity_month,
        COUNT(DISTINCT p.Id) as posts_created,
        COUNT(DISTINCT c.Id) as comments_made,
        COUNT(DISTINCT v.Id) as votes_cast,
        AVG(p.Score) as avg_post_score
    FROM Users u
    INNER JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId AND DATE_TRUNC('month', c.CreationDate) = DATE_TRUNC('month', p.CreationDate)
    LEFT JOIN Votes v ON u.Id = v.UserId AND DATE_TRUNC('month', v.CreationDate) = DATE_TRUNC('month', p.CreationDate)
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
    GROUP BY u.Id, DATE_TRUNC('month', p.CreationDate)
)
SELECT 
    hvu.DisplayName,
    hvu.Reputation,
    hvu.badge_count,
    hvu.gold_badges,
    tp.tag_name,
    tp.avg_score as tag_avg_score,
    tp.avg_views as tag_avg_views,
    COUNT(DISTINCT qam.question_id) as questions_in_tag,
    COUNT(DISTINCT qam.answer_id) as answers_in_tag,
    AVG(qam.answer_score) as avg_answer_score,
    AVG(qam.hours_to_answer) as avg_hours_to_answer,
    SUM(qam.is_accepted) as accepted_answers,
    AVG(uet.posts_created) as avg_monthly_posts,
    AVG(uet.comments_made) as avg_monthly_comments,
    MAX(uet.activity_month) as last_active_month,
    RANK() OVER (PARTITION BY tp.tag_name ORDER BY COUNT(DISTINCT qam.answer_id) DESC, AVG(qam.answer_score) DESC) as user_rank_in_tag
FROM high_value_users hvu
INNER JOIN question_answer_metrics qam ON hvu.Id = qam.answer_owner_id
INNER JOIN Posts p ON qam.question_id = p.Id
INNER JOIN tag_performance tp ON unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) = tp.tag_name
LEFT JOIN user_engagement_timeline uet ON hvu.Id = uet.user_id
WHERE qam.answer_score >= 3
    AND tp.questions_count >= 100
GROUP BY 
    hvu.Id, hvu.DisplayName, hvu.Reputation, hvu.badge_count, hvu.gold_badges,
    tp.tag_name, tp.avg_score, tp.avg_views, tp.questions_count
HAVING COUNT(DISTINCT qam.answer_id) >= 5
ORDER BY tp.questions_count DESC, hvu.Reputation DESC, avg_answer_score DESC
LIMIT 500;
