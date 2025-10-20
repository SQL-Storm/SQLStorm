-- {"query": "16070.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 165785, "output_tokens": 152769} 
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
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.CreationDate >= '2020-01-01'
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class <= 2
    WHERE u.Reputation > 1000
        AND (u.Location IS NOT NULL OR u.UpVotes > 100)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
    HAVING COUNT(DISTINCT p.Id) > 5
),
post_engagement_stats AS (
    SELECT 
        p.Id as post_id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        COALESCE(p.CommentCount, 0) as comment_count,
        LENGTH(COALESCE(p.Body, '')) as body_length,
        CASE 
            WHEN p.Tags IS NOT NULL THEN ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'), 1)
            ELSE 0 
        END as tag_count,
        AVG(v.BountyAmount) FILTER (WHERE v.VoteTypeId IN (8, 9)) OVER (PARTITION BY p.OwnerUserId) as avg_bounty,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) OVER (PARTITION BY p.Id) as upvote_count,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) OVER (PARTITION BY p.Id) as downvote_count,
        LAG(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_post_date,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as next_post_score
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.CreationDate BETWEEN '2019-01-01' AND '2023-12-31'
        AND p.PostTypeId IN (1, 2)
        AND (p.ClosedDate IS NULL OR p.Score > 0)
),
complex_join_analysis AS (
    SELECT 
        uam.Id as user_id,
        uam.DisplayName,
        uam.location_rank,
        pes.post_id,
        pes.Score as post_score,
        pes.tag_count,
        COALESCE(accepted_ans.Score, 0) as accepted_answer_score,
        EXISTS (
            SELECT 1 FROM Comments c 
            WHERE c.PostId = pes.post_id 
                AND c.Score > 5 
                AND c.Text ILIKE '%thanks%'
        ) as has_grateful_comment,
        (
            SELECT COUNT(DISTINCT pl.RelatedPostId)
            FROM PostLinks pl
            WHERE pl.PostId = pes.post_id AND pl.LinkTypeId = 1
        ) as linked_posts_count,
        (
            SELECT STRING_AGG(DISTINCT SUBSTRING(ph.Comment, 1, 50), '; ' ORDER BY SUBSTRING(ph.Comment, 1, 50))
            FROM PostHistory ph
            WHERE ph.PostId = pes.post_id 
                AND ph.PostHistoryTypeId IN (4, 5, 6)
                AND ph.Comment IS NOT NULL
            LIMIT 3
        ) as edit_comments,
        CASE 
            WHEN pes.upvote_count > 50 THEN 'Highly Popular'
            WHEN pes.upvote_count > 20 THEN 'Popular'
            WHEN pes.upvote_count > 5 THEN 'Moderate'
            WHEN pes.downvote_count > pes.upvote_count THEN 'Controversial'
            ELSE 'Low Engagement'
        END as engagement_category,
        EXTRACT(EPOCH FROM (pes.prev_post_date - LAG(pes.prev_post_date, 1) OVER (PARTITION BY uam.Id ORDER BY pes.post_id))) / 3600.0 as hours_between_posts,
        NULLIF(pes.body_length, 0) / NULLIF(pes.comment_count + 1, 0) as content_to_comment_ratio
    FROM user_activity_metrics uam
    INNER JOIN post_engagement_stats pes ON uam.Id = pes.OwnerUserId
    LEFT JOIN Posts parent_post ON pes.post_id = parent_post.Id AND pes.PostTypeId = 2
    LEFT JOIN Posts accepted_ans ON parent_post.AcceptedAnswerId = accepted_ans.Id
    WHERE uam.location_rank <= 10
        AND pes.avg_bounty IS NOT NULL OR pes.ViewCount > 1000
)
SELECT 
    cja.user_id,
    UPPER(COALESCE(NULLIF(TRIM(cja.DisplayName), ''), 'Anonymous User')) as normalized_display_name,
    cja.engagement_category,
    COUNT(DISTINCT cja.post_id) as analyzed_posts,
    ROUND(AVG(cja.post_score)::numeric, 2) as avg_post_score,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY cja.content_to_comment_ratio)::numeric, 2) as median_content_ratio,
    MAX(cja.accepted_answer_score) as best_accepted_answer,
    SUM(CASE WHEN cja.has_grateful_comment THEN 1 ELSE 0 END) as grateful_comments_total,
    ROUND(AVG(NULLIF(cja.hours_between_posts, 0))::numeric, 1) as avg_hours_between_posts,
    STRING_AGG(DISTINCT SUBSTRING(cja.edit_comments, 1, 100), ' | ') as sample_edits,
    SUM(cja.linked_posts_count) as total_links,
    CASE 
        WHEN AVG(cja.tag_count) >= 4 THEN 'Over-tagged'
        WHEN AVG(cja.tag_count) >= 2 THEN 'Well-tagged'
        ELSE 'Under-tagged'
    END as tagging_behavior
FROM complex_join_analysis cja
WHERE cja.post_score > -5
    AND (cja.linked_posts_count > 0 OR cja.has_grateful_comment = TRUE)
GROUP BY cja.user_id, cja.DisplayName, cja.engagement_category
HAVING COUNT(DISTINCT cja.post_id) >= 3
    AND AVG(cja.post_score) > 0
UNION ALL
SELECT 
    -1 as user_id,
    'AGGREGATE_SUMMARY' as normalized_display_name,
    'Overall' as engagement_category,
    COUNT(DISTINCT post_id) as analyzed_posts,
    ROUND(AVG(post_score)::numeric, 2) as avg_post_score,
    NULL as median_content_ratio,
    NULL as best_accepted_answer,
    NULL as grateful_comments_total,
    NULL as avg_hours_between_posts,
    'N/A' as sample_edits,
    NULL as total_links,
    NULL as tagging_behavior
FROM complex_join_analysis
ORDER BY user_id DESC, avg_post_score DESC NULLS LAST, analyzed_posts DESC
LIMIT 500;