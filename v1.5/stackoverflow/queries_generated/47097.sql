-- {"query": "47097.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 1837}

WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT pt.Id) as question_count,
        1 as level
    FROM Tags t
    JOIN Posts pt ON pt.Tags LIKE '%<' || t.TagName || '>%'
    WHERE pt.PostTypeId = 1
        AND t.Count > 1000
    GROUP BY t.Id, t.TagName
),
user_expertise AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        t.TagName,
        COUNT(DISTINCT p.Id) as answers_in_tag,
        SUM(p.Score) as total_score_in_tag,
        AVG(p.Score) as avg_score_in_tag,
        RANK() OVER (PARTITION BY t.TagName ORDER BY SUM(p.Score) DESC) as tag_rank
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    JOIN Posts q ON q.Id = p.ParentId
    JOIN Tags t ON q.Tags LIKE '%<' || t.TagName || '>%'
    WHERE p.PostTypeId = 2
        AND u.Reputation > 5000
        AND p.Score > 0
        AND q.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName, u.Reputation, t.TagName
    HAVING COUNT(DISTINCT p.Id) >= 10
),
monthly_activity AS (
    SELECT 
        DATE_TRUNC('month', p.CreationDate) as activity_month,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answers,
        COUNT(DISTINCT p.OwnerUserId) as active_users,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount END) as avg_views,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as median_score,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY p.Score) as p95_score
    FROM Posts p
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
        AND p.OwnerUserId IS NOT NULL
    GROUP BY DATE_TRUNC('month', p.CreationDate)
),
badge_patterns AS (
    SELECT 
        b.UserId,
        STRING_AGG(DISTINCT b.Name, ', ' ORDER BY b.Name) FILTER (WHERE b.Class = 1) as gold_badges,
        STRING_AGG(DISTINCT b.Name, ', ' ORDER BY b.Name) FILTER (WHERE b.Class = 2) as silver_badges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) as gold_count,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) as silver_count,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) as bronze_count,
        MIN(b.Date) as first_badge_date,
        MAX(b.Date) as last_badge_date
    FROM Badges b
    GROUP BY b.UserId
),
complex_interactions AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        COUNT(DISTINCT c.UserId) as unique_commenters,
        COUNT(DISTINCT ph.UserId) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) as unique_editors,
        COUNT(DISTINCT v.UserId) FILTER (WHERE v.VoteTypeId = 2) as upvoters,
        COUNT(DISTINCT v.UserId) FILTER (WHERE v.VoteTypeId = 3) as downvoters,
        COUNT(DISTINCT pl.RelatedPostId) as linked_posts,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') as tags_list,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN p.AnswerCount > 0 THEN 'Has Answers'
            ELSE 'Open'
        END as status
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
        AND p.ViewCount > 1000
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.Tags, p.ClosedDate, p.AcceptedAnswerId, p.AnswerCount
)
SELECT 
    ma.activity_month,
    ma.questions,
    ma.answers,
    ma.active_users,
    ROUND(ma.avg_views, 2) as avg_views,
    ma.median_score,
    ma.p95_score,
    COUNT(DISTINCT ue.UserId) as expert_users,
    AVG(ue.Reputation) as avg_expert_reputation,
    COUNT(DISTINCT ci.PostId) as high_activity_posts,
    AVG(ci.unique_commenters) as avg_commenters_per_post,
    AVG(ci.unique_editors) as avg_editors_per_post,
    SUM(bp.gold_count) as total_gold_badges,
    SUM(bp.silver_count) as total_silver_badges,
    SUM(bp.bronze_count) as total_bronze_badges,
    COUNT(DISTINCT th.TagName) as popular_tags,
    COALESCE(AVG(ci.upvoters::FLOAT / NULLIF(ci.downvoters, 0)), 0) as avg_upvote_downvote_ratio,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY ci.ViewCount) as p75_views,
    STRING_AGG(DISTINCT ue.TagName, ', ' ORDER BY ue.TagName) FILTER (WHERE ue.tag_rank <= 3) as top_expertise_areas
FROM monthly_activity ma
LEFT JOIN user_expertise ue ON DATE_TRUNC('month', CURRENT_DATE) = ma.activity_month
LEFT JOIN badge_patterns bp ON bp.UserId = ue.UserId
LEFT JOIN complex_interactions ci ON DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 year') <= ma.activity_month
LEFT JOIN tag_hierarchy th ON th.question_count > 100
WHERE ma.activity_month >= CURRENT_DATE - INTERVAL '18 months'
GROUP BY 
    ma.activity_month,
    ma.questions,
    ma.answers,
    ma.active_users,
    ma.avg_views,
    ma.median_score,
    ma.p95_score
ORDER BY ma.activity_month DESC;
