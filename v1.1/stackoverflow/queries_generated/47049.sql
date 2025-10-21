-- {"query": "47049.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 1966}

WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT p.Id) as question_count,
        1 as level
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%'
    WHERE p.PostTypeId = 1
        AND t.Count > 1000
    GROUP BY t.Id, t.TagName
    
    UNION ALL
    
    SELECT 
        t.Id,
        t.TagName,
        th.question_count,
        th.level + 1
    FROM Tags t
    INNER JOIN tag_hierarchy th ON th.Id != t.Id
    INNER JOIN Posts p1 ON p1.Tags LIKE '%<' || th.TagName || '>%'
    INNER JOIN Posts p2 ON p2.Tags LIKE '%<' || t.TagName || '>%'
        AND p1.Id = p2.Id
    WHERE th.level < 3
        AND t.Count > 500
),
user_expertise AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        t.TagName,
        COUNT(DISTINCT p.Id) as answers_in_tag,
        AVG(p.Score) as avg_answer_score,
        SUM(p.Score) as total_tag_score,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as median_score,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId = p.Id THEN p.Id END) as accepted_answers,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY SUM(p.Score) DESC) as tag_rank
    FROM Users u
    INNER JOIN Posts p ON p.OwnerUserId = u.Id
    INNER JOIN Posts q ON q.Id = p.ParentId
    INNER JOIN Tags t ON q.Tags LIKE '%<' || t.TagName || '>%'
    WHERE p.PostTypeId = 2
        AND p.Score > 0
        AND u.Reputation > 5000
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, t.TagName
    HAVING COUNT(DISTINCT p.Id) >= 10
),
temporal_patterns AS (
    SELECT 
        DATE_TRUNC('month', p.CreationDate) as month,
        pt.Name as post_type,
        COUNT(*) as post_count,
        AVG(p.Score) as avg_score,
        STDDEV(p.Score) as score_stddev,
        AVG(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) as avg_views,
        AVG(p.AnswerCount) FILTER (WHERE p.PostTypeId = 1) as avg_answers,
        COUNT(DISTINCT p.OwnerUserId) as unique_contributors,
        SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END)::FLOAT / NULLIF(COUNT(*), 0) as close_rate,
        LAG(COUNT(*), 1) OVER (PARTITION BY pt.Name ORDER BY DATE_TRUNC('month', p.CreationDate)) as prev_month_count,
        LAG(COUNT(*), 12) OVER (PARTITION BY pt.Name ORDER BY DATE_TRUNC('month', p.CreationDate)) as year_ago_count
    FROM Posts p
    INNER JOIN PostTypes pt ON pt.Id = p.PostTypeId
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '3 years'
    GROUP BY DATE_TRUNC('month', p.CreationDate), pt.Name
),
badge_networks AS (
    SELECT 
        b1.UserId as user1,
        b2.UserId as user2,
        COUNT(DISTINCT b1.Name) as common_badges,
        STRING_AGG(DISTINCT b1.Name, ', ' ORDER BY b1.Name) as badge_list,
        MIN(ABS(EXTRACT(EPOCH FROM (b1.Date - b2.Date)))) as min_time_diff_seconds
    FROM Badges b1
    INNER JOIN Badges b2 ON b1.Name = b2.Name 
        AND b1.UserId < b2.UserId
        AND b1.Class = b2.Class
    WHERE b1.TagBased = '0'
    GROUP BY b1.UserId, b2.UserId
    HAVING COUNT(DISTINCT b1.Name) >= 5
)
SELECT 
    ue.DisplayName,
    ue.TagName,
    ue.answers_in_tag,
    ue.avg_answer_score,
    ue.total_tag_score,
    ue.median_score,
    ue.accepted_answers,
    ue.tag_rank,
    th.question_count as tag_question_count,
    tp.avg_score as monthly_avg_score,
    tp.score_stddev,
    tp.avg_views,
    tp.close_rate,
    CASE 
        WHEN tp.prev_month_count IS NULL THEN NULL
        ELSE ((tp.post_count - tp.prev_month_count)::FLOAT / NULLIF(tp.prev_month_count, 0)) * 100
    END as month_over_month_growth,
    CASE 
        WHEN tp.year_ago_count IS NULL THEN NULL
        ELSE ((tp.post_count - tp.year_ago_count)::FLOAT / NULLIF(tp.year_ago_count, 0)) * 100
    END as year_over_year_growth,
    bn.common_badges,
    bn.badge_list,
    u.Reputation,
    u.CreationDate as user_since,
    COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) as total_edits,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) as upvotes_cast,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) as downvotes_cast,
    COUNT(DISTINCT c.Id) as comments_made,
    AVG(c.Score) as avg_comment_score
FROM user_expertise ue
INNER JOIN Users u ON u.Id = ue.UserId
LEFT JOIN tag_hierarchy th ON th.TagName = ue.TagName
LEFT JOIN temporal_patterns tp ON tp.month = DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month')
    AND tp.post_type = 'Answer'
LEFT JOIN badge_networks bn ON bn.user1 = ue.UserId OR bn.user2 = ue.UserId
LEFT JOIN PostHistory ph ON ph.UserId = ue.UserId
LEFT JOIN Votes v ON v.UserId = ue.UserId
LEFT JOIN Comments c ON c.UserId = ue.UserId
WHERE ue.tag_rank <= 10
GROUP BY 
    ue.DisplayName, ue.TagName, ue.answers_in_tag, ue.avg_answer_score,
    ue.total_tag_score, ue.median_score, ue.accepted_answers, ue.tag_rank,
    th.question_count, tp.avg_score, tp.score_stddev, tp.avg_views,
    tp.close_rate, tp.post_count, tp.prev_month_count, tp.year_ago_count,
    bn.common_badges, bn.badge_list, u.Reputation, u.CreationDate
ORDER BY ue.total_tag_score DESC, ue.TagName, ue.tag_rank
LIMIT 100;
