-- {"query": "16083.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 196140, "output_tokens": 182422} 

WITH user_activity_metrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.Location,
        COUNT(DISTINCT p.Id) as post_count,
        COUNT(DISTINCT b.Id) as badge_count,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as question_score,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as answer_score,
        ROW_NUMBER() OVER (PARTITION BY SUBSTRING(COALESCE(u.Location, 'Unknown'), 1, 20) ORDER BY u.Reputation DESC) as location_rank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT b.Id) DESC) as badge_rank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.CreationDate >= TIMESTAMP '2020-01-01'
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class <= 2
    WHERE u.Reputation > 100 
        AND u.CreationDate >= TIMESTAMP '2015-01-01'
        AND (u.Location IS NULL OR LENGTH(TRIM(u.Location)) > 0)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
    HAVING COUNT(DISTINCT p.Id) > 5
),
post_engagement_stats AS (
    SELECT 
        p.Id as post_id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        COALESCE(p.AnswerCount, 0) as answer_cnt,
        COUNT(DISTINCT c.Id) as comment_cnt,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) as upvote_cnt,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) as downvote_cnt,
        STRING_AGG(DISTINCT COALESCE(c.Text, ''), ' | ') as concatenated_comments,
        AVG(c.Score) OVER (PARTITION BY p.OwnerUserId) as avg_comment_score_per_user,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_post_score,
        LEAD(p.ViewCount, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as next_post_views
    FROM Posts p
    INNER JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Comments c ON p.Id = c.PostId AND c.Score > 0
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.CreationDate >= TIMESTAMP '2019-01-01'
    WHERE p.PostTypeId IN (1, 2)
        AND p.Score BETWEEN -5 AND 1000
        AND (p.ClosedDate IS NULL OR p.ClosedDate > TIMESTAMP '2021-01-01')
        AND COALESCE(p.ViewCount, 0) >= 10
    GROUP BY p.Id, p.Title, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount, p.CreationDate
),
tag_correlations AS (
    SELECT 
        t.TagName,
        t.Count as tag_usage_count,
        COUNT(DISTINCT pl.RelatedPostId) as related_post_count,
        AVG(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1.0 ELSE 0.0 END) as acceptance_rate
    FROM Tags t
    INNER JOIN Posts p ON POSITION('<' || t.TagName || '>' IN COALESCE(p.Tags, '')) > 0
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 1
    WHERE t.Count > 100
        AND t.IsModeratorOnly = 0
        AND LENGTH(t.TagName) BETWEEN 2 AND 25
    GROUP BY t.TagName, t.Count
    HAVING COUNT(DISTINCT p.Id) > 50
)
SELECT 
    uam.DisplayName,
    UPPER(COALESCE(SUBSTRING(uam.Location, 1, 30), 'N/A')) as normalized_location,
    uam.Reputation,
    uam.post_count,
    uam.badge_count,
    uam.question_score + uam.answer_score as total_score,
    ROUND(CAST(uam.question_score AS NUMERIC) / NULLIF(uam.answer_score, 0), 2) as question_answer_ratio,
    pes.post_id,
    COALESCE(SUBSTRING(pes.Title, 1, 50), '[No Title]') as truncated_title,
    pes.Score as post_score,
    pes.answer_cnt,
    pes.comment_cnt,
    pes.upvote_cnt - pes.downvote_cnt as net_votes,
    CASE 
        WHEN pes.ViewCount > 10000 THEN 'Viral'
        WHEN pes.ViewCount > 1000 THEN 'Popular'
        WHEN pes.ViewCount > 100 THEN 'Moderate'
        ELSE 'Low'
    END as view_category,
    CASE 
        WHEN pes.prev_post_score > pes.Score THEN 'Declining'
        WHEN pes.prev_post_score < pes.Score THEN 'Improving'
        ELSE 'Stable'
    END as score_trend,
    tc.TagName as primary_tag,
    tc.tag_usage_count,
    ROUND(tc.acceptance_rate * 100, 2) as tag_acceptance_pct,
    (SELECT COUNT(*) 
     FROM PostHistory ph 
     WHERE ph.PostId = pes.post_id 
        AND ph.PostHistoryTypeId IN (4, 5, 6)
        AND ph.UserId IS NOT NULL) as edit_count,
    EXISTS(
        SELECT 1 
        FROM Votes v2 
        WHERE v2.PostId = pes.post_id 
            AND v2.VoteTypeId = 8 
            AND v2.BountyAmount >= 50
    ) as has_bounty,
    uam.location_rank,
    uam.badge_rank,
    NTILE(10) OVER (ORDER BY uam.Reputation DESC, uam.post_count DESC) as decile_rank
FROM user_activity_metrics uam
INNER JOIN post_engagement_stats pes ON uam.Id = pes.OwnerUserId
LEFT OUTER JOIN Posts p2 ON pes.post_id = p2.Id
LEFT OUTER JOIN tag_correlations tc ON POSITION('<' || tc.TagName || '>' IN COALESCE(p2.Tags, '')) > 0
WHERE uam.location_rank <= 3
    AND pes.upvote_cnt > pes.downvote_cnt
    AND (pes.comment_cnt > 2 OR pes.answer_cnt > 0)
    AND (tc.acceptance_rate IS NULL OR tc.acceptance_rate >= 0.3)
    AND NOT EXISTS (
        SELECT 1 
        FROM Votes v3 
        WHERE v3.PostId = pes.post_id 
            AND v3.VoteTypeId IN (4, 12)
    )
ORDER BY 
    uam.Reputation DESC,
    pes.Score DESC,
    pes.ViewCount DESC NULLS LAST,
    tc.tag_usage_count DESC NULLS LAST
LIMIT 500;
