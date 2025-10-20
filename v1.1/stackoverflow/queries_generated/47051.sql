-- {"query": "47051.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 116994, "output_tokens": 103333} 

WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT pt.Id) as direct_questions,
        t.Count as total_uses
    FROM Tags t
    INNER JOIN Posts pt ON pt.Tags LIKE '%<' || t.TagName || '>%'
    WHERE pt.PostTypeId = 1
        AND pt.Score >= 10
        AND t.Count >= 1000
    GROUP BY t.Id, t.TagName, t.Count
),
expert_users AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Name) as unique_badges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) as gold_badges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) as silver_badges,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) as reputation_rank
    FROM Users u
    INNER JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation >= 10000
        AND u.LastAccessDate >= CURRENT_DATE - INTERVAL '180 days'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT b.Name) >= 20
),
question_quality_metrics AS (
    SELECT 
        q.Id as QuestionId,
        q.OwnerUserId,
        q.Score as QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        AVG(a.Score) as avg_answer_score,
        MAX(a.Score) as best_answer_score,
        COUNT(DISTINCT a.OwnerUserId) as unique_answerers,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY a.Score) as answer_score_75th,
        SUM(CASE WHEN a.Score >= 5 THEN 1 ELSE 0 END) as high_quality_answers,
        EXTRACT(EPOCH FROM (MIN(a.CreationDate) - q.CreationDate))/3600.0 as hours_to_first_answer,
        EXTRACT(EPOCH FROM (COALESCE(q.ClosedDate, CURRENT_TIMESTAMP) - q.CreationDate))/86400.0 as days_open
    FROM Posts q
    INNER JOIN Posts a ON a.ParentId = q.Id
    WHERE q.PostTypeId = 1
        AND a.PostTypeId = 2
        AND q.CreationDate >= CURRENT_DATE - INTERVAL '365 days'
        AND q.Score >= 5
        AND q.ViewCount >= 1000
    GROUP BY q.Id, q.OwnerUserId, q.Score, q.ViewCount, q.AnswerCount, q.FavoriteCount, q.ClosedDate, q.CreationDate
    HAVING COUNT(a.Id) >= 3
),
user_activity_patterns AS (
    SELECT 
        ph.UserId,
        DATE_TRUNC('month', ph.CreationDate) as activity_month,
        COUNT(DISTINCT ph.PostId) as posts_edited,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (2,5,8) THEN ph.PostId END) as body_edits,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (3,6,9) THEN ph.PostId END) as tag_edits,
        COUNT(DISTINCT DATE(ph.CreationDate)) as active_days,
        AVG(LENGTH(ph.Text)) as avg_edit_size
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
        AND ph.CreationDate >= CURRENT_DATE - INTERVAL '365 days'
        AND ph.PostHistoryTypeId IN (2,3,4,5,6,7,8,9)
    GROUP BY ph.UserId, DATE_TRUNC('month', ph.CreationDate)
),
cross_referenced_posts AS (
    SELECT 
        pl.PostId,
        pl.RelatedPostId,
        p1.Score as post_score,
        p2.Score as related_score,
        p1.ViewCount as post_views,
        p2.ViewCount as related_views,
        COUNT(DISTINCT pl2.PostId) as shared_links,
        STRING_AGG(DISTINCT p1.Tags, ',') as combined_tags
    FROM PostLinks pl
    INNER JOIN Posts p1 ON pl.PostId = p1.Id
    INNER JOIN Posts p2 ON pl.RelatedPostId = p2.Id
    LEFT JOIN PostLinks pl2 ON pl2.RelatedPostId = pl.RelatedPostId AND pl2.PostId != pl.PostId
    WHERE pl.LinkTypeId = 1
        AND p1.PostTypeId = 1
        AND p2.PostTypeId = 1
    GROUP BY pl.PostId, pl.RelatedPostId, p1.Score, p2.Score, p1.ViewCount, p2.ViewCount
)
SELECT 
    eu.DisplayName,
    eu.Reputation,
    eu.gold_badges,
    eu.silver_badges,
    COUNT(DISTINCT qm.QuestionId) as quality_questions_owned,
    AVG(qm.QuestionScore) as avg_question_score,
    AVG(qm.avg_answer_score) as avg_answer_score_received,
    SUM(qm.ViewCount) as total_views,
    AVG(qm.hours_to_first_answer) as avg_hours_to_first_answer,
    COUNT(DISTINCT uap.activity_month) as active_months,
    SUM(uap.posts_edited) as total_posts_edited,
    AVG(uap.avg_edit_size) as avg_edit_size,
    COUNT(DISTINCT crp.PostId) as linked_posts,
    AVG(crp.shared_links) as avg_shared_links,
    COALESCE(STRING_AGG(DISTINCT th.TagName, ', ' ORDER BY th.total_uses DESC) FILTER (WHERE th.total_uses >= 5000), 'None') as top_tags,
    ROW_NUMBER() OVER (ORDER BY eu.Reputation DESC, COUNT(DISTINCT qm.QuestionId) DESC) as overall_rank
FROM expert_users eu
LEFT JOIN question_quality_metrics qm ON qm.OwnerUserId = eu.UserId
LEFT JOIN user_activity_patterns uap ON uap.UserId = eu.UserId
LEFT JOIN cross_referenced_posts crp ON crp.PostId = qm.QuestionId
LEFT JOIN Posts p ON p.OwnerUserId = eu.UserId AND p.PostTypeId = 1
LEFT JOIN tag_hierarchy th ON p.Tags LIKE '%<' || th.TagName || '>%'
WHERE eu.reputation_rank <= 100
GROUP BY eu.UserId, eu.DisplayName, eu.Reputation, eu.gold_badges, eu.silver_badges, eu.unique_badges, eu.reputation_rank
HAVING COUNT(DISTINCT qm.QuestionId) >= 5
    OR SUM(uap.posts_edited) >= 50
ORDER BY overall_rank
LIMIT 50;
