-- {"query": "16058.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 137765, "output_tokens": 127834} 

WITH user_engagement_metrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.Location,
        COUNT(DISTINCT p.Id) as post_count,
        COUNT(DISTINCT c.Id) as comment_count,
        COUNT(DISTINCT b.Id) as badge_count,
        AVG(p.Score) as avg_post_score,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as question_count,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as answer_count,
        ROW_NUMBER() OVER (PARTITION BY COALESCE(SUBSTRING(u.Location, 1, POSITION(',' IN u.Location || ',') - 1), 'Unknown') ORDER BY u.Reputation DESC) as location_rank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2020-01-01'
        AND u.Reputation > 100
        AND (u.Location IS NOT NULL OR u.Reputation > 1000)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
    HAVING COUNT(DISTINCT p.Id) > 5
),
post_interaction_analysis AS (
    SELECT 
        p.Id as post_id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.OwnerUserId,
        COALESCE(p.FavoriteCount, 0) as favorite_count,
        DENSE_RANK() OVER (PARTITION BY EXTRACT(YEAR FROM p.CreationDate) ORDER BY p.ViewCount DESC NULLS LAST) as yearly_view_rank,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as next_score,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as user_total_posts,
        SUM(COALESCE(p.Score, 0)) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) as cumulative_score,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) as duplicate_count,
        (SELECT STRING_AGG(DISTINCT vt.Name, '; ') 
         FROM Votes v 
         INNER JOIN VoteTypes vt ON v.VoteTypeId = vt.Id 
         WHERE v.PostId = p.Id AND v.VoteTypeId IN (2, 3, 8)) as vote_types
    FROM Posts p
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= '2019-01-01'
        AND p.Score IS NOT NULL
        AND (p.ClosedDate IS NULL OR p.ClosedDate > p.CreationDate + INTERVAL '30 days')
),
tag_popularity_trends AS (
    SELECT 
        t.TagName,
        t.Count as tag_count,
        COUNT(DISTINCT p.Id) as recent_posts,
        AVG(p.Score) as avg_score,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.ViewCount) as median_views,
        MAX(p.CreationDate) as last_used,
        CASE 
            WHEN t.Count > 10000 THEN 'Very Popular'
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Niche'
        END as popularity_tier
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%'
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= '2018-01-01'
        AND t.Count > 50
    GROUP BY t.TagName, t.Count
),
complex_post_metrics AS (
    SELECT 
        pia.post_id,
        pia.Title,
        pia.OwnerUserId,
        uem.DisplayName,
        uem.location_rank,
        pia.Score * COALESCE(LOG(NULLIF(pia.ViewCount, 0) + 1), 0) as engagement_score,
        CASE 
            WHEN pia.AnswerCount = 0 THEN 'Unanswered'
            WHEN pia.AnswerCount <= 2 THEN 'Few Answers'
            WHEN pia.AnswerCount <= 5 THEN 'Multiple Answers'
            ELSE 'Many Answers'
        END as answer_category,
        COALESCE(pia.prev_score, 0) + COALESCE(pia.next_score, 0) as surrounding_score,
        pia.cumulative_score,
        (SELECT COUNT(*) 
         FROM PostHistory ph 
         WHERE ph.PostId = pia.post_id 
            AND ph.PostHistoryTypeId IN (4, 5, 6)
            AND ph.UserId != pia.OwnerUserId) as external_edit_count,
        (SELECT AVG(c.Score)
         FROM Comments c
         WHERE c.PostId = pia.post_id
            AND c.Score IS NOT NULL) as avg_comment_score,
        pia.vote_types,
        pia.duplicate_count
    FROM post_interaction_analysis pia
    INNER JOIN user_engagement_metrics uem ON pia.OwnerUserId = uem.Id
    WHERE pia.yearly_view_rank <= 1000
        AND pia.user_total_posts >= 3
        AND (pia.Score >= 5 OR pia.ViewCount > 500)
)
SELECT 
    cpm.Title,
    cpm.DisplayName,
    cpm.location_rank,
    cpm.engagement_score,
    cpm.answer_category,
    cpm.surrounding_score,
    cpm.cumulative_score,
    cpm.external_edit_count,
    ROUND(CAST(cpm.avg_comment_score as numeric), 2) as avg_comment_score,
    cpm.vote_types,
    cpm.duplicate_count,
    tpt1.popularity_tier as primary_tag_tier,
    tpt1.avg_score as primary_tag_avg_score,
    COALESCE(tpt2.TagName, 'N/A') as secondary_tag,
    CASE 
        WHEN cpm.engagement_score > (SELECT AVG(engagement_score) * 2 FROM complex_post_metrics) THEN 'Exceptional'
        WHEN cpm.engagement_score > (SELECT AVG(engagement_score) FROM complex_post_metrics) THEN 'Above Average'
        ELSE 'Average'
    END as relative_performance,
    (SELECT COUNT(DISTINCT b.Id) 
     FROM Badges b 
     WHERE b.UserId = cpm.OwnerUserId 
        AND b.Class = 1
        AND b.Date >= '2020-01-01') as gold_badges_recent
FROM complex_post_metrics cpm
LEFT JOIN LATERAL (
    SELECT tpt.TagName, tpt.popularity_tier, tpt.avg_score
    FROM tag_popularity_trends tpt
    INNER JOIN Posts p ON p.Id = cpm.post_id
    WHERE p.Tags LIKE '%<' || tpt.TagName || '>%'
    ORDER BY tpt.tag_count DESC
    LIMIT 1
) tpt1 ON true
LEFT JOIN LATERAL (
    SELECT tpt.TagName
    FROM tag_popularity_trends tpt
    INNER JOIN Posts p ON p.Id = cpm.post_id
    WHERE p.Tags LIKE '%<' || tpt.TagName || '>%'
        AND tpt.TagName != COALESCE(tpt1.TagName, '')
    ORDER BY tpt.tag_count DESC
    LIMIT 1
) tpt2 ON true
WHERE cpm.engagement_score > 0
    AND (cpm.external_edit_count > 0 OR cpm.cumulative_score > 100)
    AND cpm.location_rank <= 50
ORDER BY cpm.engagement_score DESC, cpm.cumulative_score DESC
LIMIT 500;
