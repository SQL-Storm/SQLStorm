-- {"query": "47041.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 94054, "output_tokens": 83363} 

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
    FROM tag_hierarchy th
    CROSS JOIN Tags t
    WHERE th.level < 3
        AND t.Count > 500
),
user_expertise AS (
    SELECT 
        u.Id as user_id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as questions_asked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answers_given,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score > 10 THEN p.Id END) as high_score_answers,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) as gold_badges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) as silver_badges,
        COALESCE(AVG(p.Score) FILTER (WHERE p.PostTypeId = 2), 0) as avg_answer_score,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) FILTER (WHERE p.PostTypeId = 2) as median_answer_score,
        MAX(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) as max_question_views
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation > 5000
        AND u.LastAccessDate > (CURRENT_TIMESTAMP - INTERVAL '365 days')
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
post_evolution AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        COUNT(DISTINCT ph.Id) as edit_count,
        COUNT(DISTINCT ph.UserId) as unique_editors,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) as was_closed,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) as was_reopened,
        STRING_AGG(DISTINCT pht.Name, ', ' ORDER BY pht.Name) as history_types,
        EXTRACT(EPOCH FROM (MAX(ph.CreationDate) - MIN(ph.CreationDate)))/3600 as hours_between_first_last_edit
    FROM Posts p
    INNER JOIN PostHistory ph ON ph.PostId = p.Id
    INNER JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
    WHERE p.PostTypeId = 1
        AND p.Score > 50
        AND p.CreationDate > (CURRENT_TIMESTAMP - INTERVAL '730 days')
    GROUP BY p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount
    HAVING COUNT(DISTINCT ph.Id) > 5
),
comment_analysis AS (
    SELECT 
        p.Id as post_id,
        COUNT(c.Id) as comment_count,
        AVG(c.Score) as avg_comment_score,
        COUNT(DISTINCT c.UserId) as unique_commenters,
        MAX(c.Score) as max_comment_score,
        STDDEV(c.Score) as comment_score_stddev
    FROM Posts p
    INNER JOIN Comments c ON c.PostId = p.Id
    WHERE p.PostTypeId IN (1, 2)
        AND p.Score > 20
    GROUP BY p.Id
),
vote_patterns AS (
    SELECT 
        DATE_TRUNC('month', v.CreationDate) as vote_month,
        vt.Name as vote_type,
        COUNT(*) as vote_count,
        COUNT(DISTINCT v.UserId) as unique_voters,
        COUNT(DISTINCT v.PostId) as unique_posts_voted,
        AVG(v.BountyAmount) FILTER (WHERE v.VoteTypeId = 8) as avg_bounty_amount,
        LAG(COUNT(*), 1) OVER (PARTITION BY vt.Name ORDER BY DATE_TRUNC('month', v.CreationDate)) as prev_month_count,
        LEAD(COUNT(*), 1) OVER (PARTITION BY vt.Name ORDER BY DATE_TRUNC('month', v.CreationDate)) as next_month_count
    FROM Votes v
    INNER JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate > (CURRENT_TIMESTAMP - INTERVAL '180 days')
    GROUP BY DATE_TRUNC('month', v.CreationDate), vt.Name
)
SELECT 
    ue.DisplayName,
    ue.Reputation,
    ue.questions_asked,
    ue.answers_given,
    ue.high_score_answers,
    ue.gold_badges,
    ue.silver_badges,
    ue.avg_answer_score,
    ue.median_answer_score,
    pe.Title as top_edited_post_title,
    pe.Score as post_score,
    pe.ViewCount as post_views,
    pe.edit_count,
    pe.unique_editors,
    pe.was_closed,
    pe.was_reopened,
    pe.history_types,
    pe.hours_between_first_last_edit,
    ca.comment_count,
    ca.avg_comment_score,
    ca.unique_commenters,
    ca.comment_score_stddev,
    th.TagName as related_tag,
    th.question_count as tag_question_count,
    vp.vote_type,
    vp.vote_count as recent_vote_count,
    vp.unique_voters,
    vp.avg_bounty_amount,
    CASE 
        WHEN vp.prev_month_count IS NULL THEN 0
        ELSE ROUND(((vp.vote_count - vp.prev_month_count)::numeric / NULLIF(vp.prev_month_count, 0)) * 100, 2)
    END as vote_growth_percentage,
    DENSE_RANK() OVER (ORDER BY ue.Reputation DESC, ue.gold_badges DESC) as user_rank,
    ROW_NUMBER() OVER (PARTITION BY th.TagName ORDER BY pe.Score DESC) as post_rank_in_tag
FROM user_expertise ue
CROSS JOIN LATERAL (
    SELECT * FROM post_evolution 
    ORDER BY Score DESC, ViewCount DESC 
    LIMIT 3
) pe
LEFT JOIN comment_analysis ca ON ca.post_id = pe.Id
LEFT JOIN LATERAL (
    SELECT * FROM tag_hierarchy 
    WHERE level <= 2 
    ORDER BY question_count DESC 
    LIMIT 5
) th ON TRUE
LEFT JOIN LATERAL (
    SELECT * FROM vote_patterns 
    WHERE vote_count > 100 
    ORDER BY vote_month DESC, vote_count DESC 
    LIMIT 10
) vp ON TRUE
WHERE ue.answers_given > 50
    AND ue.avg_answer_score > 5
ORDER BY 
    ue.Reputation DESC,
    pe.Score DESC,
    th.question_count DESC
LIMIT 100;
