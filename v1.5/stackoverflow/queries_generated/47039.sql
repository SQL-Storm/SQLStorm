-- {"query": "47039.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 89466, "output_tokens": 79291} 

WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT pt.Id) as direct_questions,
        ARRAY[t.TagName] as tag_path,
        1 as level
    FROM Tags t
    INNER JOIN Posts pt ON pt.Tags LIKE '%<' || t.TagName || '>%'
    WHERE pt.PostTypeId = 1
        AND t.Count > 1000
    GROUP BY t.Id, t.TagName
    
    UNION ALL
    
    SELECT 
        t2.Id,
        t2.TagName,
        th.direct_questions,
        th.tag_path || t2.TagName,
        th.level + 1
    FROM tag_hierarchy th
    CROSS JOIN Tags t2
    WHERE th.level < 3
        AND t2.Id != ALL(SELECT Id FROM Tags WHERE TagName = ANY(th.tag_path))
        AND EXISTS (
            SELECT 1 FROM Posts p 
            WHERE p.Tags LIKE '%<' || th.TagName || '>%' 
                AND p.Tags LIKE '%<' || t2.TagName || '>%'
                AND p.PostTypeId = 1
        )
),
power_users AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as total_posts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as answers,
        AVG(p.Score) as avg_score,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as median_score,
        SUM(p.Score) as total_score,
        COUNT(DISTINCT b.Name) as unique_badges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) as gold_badges,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) as reputation_rank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as activity_rank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.CreationDate >= NOW() - INTERVAL '5 years'
        AND u.Reputation > 10000
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 100
),
post_analytics AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CreationDate,
        EXTRACT(EPOCH FROM (COALESCE(p.ClosedDate, NOW()) - p.CreationDate))/3600 as hours_to_close,
        COUNT(DISTINCT ph.UserId) as unique_editors,
        COUNT(DISTINCT c.UserId) as unique_commenters,
        MAX(ph.CreationDate) - MIN(ph.CreationDate) as edit_timespan,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) as edit_count,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) as upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) as downvotes,
        ROW_NUMBER() OVER (PARTITION BY DATE_TRUNC('month', p.CreationDate) ORDER BY p.Score DESC) as monthly_rank
    FROM Posts p
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.PostTypeId = 1
        AND p.Score > 10
        AND p.CreationDate >= NOW() - INTERVAL '3 years'
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CreationDate, p.ClosedDate
)
SELECT 
    pu.DisplayName,
    pu.Reputation,
    pu.reputation_rank,
    pu.activity_rank,
    pu.total_posts,
    pu.questions,
    pu.answers,
    ROUND(pu.avg_score::numeric, 2) as avg_score,
    pu.median_score,
    pu.total_score,
    pu.unique_badges,
    pu.gold_badges,
    COUNT(DISTINCT pa.Id) as high_score_questions,
    AVG(pa.hours_to_close) as avg_hours_to_close,
    SUM(pa.unique_editors) as total_unique_editors,
    SUM(pa.unique_commenters) as total_unique_commenters,
    AVG(pa.edit_count) as avg_edits_per_post,
    SUM(pa.upvotes) as total_upvotes_received,
    SUM(pa.downvotes) as total_downvotes_received,
    ROUND((SUM(pa.upvotes)::numeric / NULLIF(SUM(pa.downvotes), 0)), 2) as upvote_downvote_ratio,
    COUNT(DISTINCT th.TagName) as unique_tag_combinations,
    STRING_AGG(DISTINCT th.TagName, ', ' ORDER BY th.TagName) FILTER (WHERE th.level = 1) as primary_tags,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY pa.ViewCount) as q75_view_count,
    STDDEV(pa.Score) as score_stddev,
    COUNT(DISTINCT DATE_TRUNC('week', pa.CreationDate)) as active_weeks,
    MAX(pa.CreationDate) as last_question_date,
    SUM(CASE WHEN pa.monthly_rank = 1 THEN 1 ELSE 0 END) as monthly_top_questions
FROM power_users pu
LEFT JOIN Posts p ON p.OwnerUserId = pu.Id AND p.PostTypeId = 1
LEFT JOIN post_analytics pa ON pa.Id = p.Id
LEFT JOIN tag_hierarchy th ON p.Tags LIKE '%<' || th.TagName || '>%'
WHERE pu.reputation_rank <= 100
GROUP BY 
    pu.DisplayName,
    pu.Reputation,
    pu.reputation_rank,
    pu.activity_rank,
    pu.total_posts,
    pu.questions,
    pu.answers,
    pu.avg_score,
    pu.median_score,
    pu.total_score,
    pu.unique_badges,
    pu.gold_badges
HAVING COUNT(DISTINCT pa.Id) > 5
ORDER BY 
    pu.reputation_rank,
    total_upvotes_received DESC,
    monthly_top_questions DESC
LIMIT 50;
