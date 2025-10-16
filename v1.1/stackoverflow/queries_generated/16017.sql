-- {"query": "16017.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 42030, "output_tokens": 38978} 

WITH user_activity_metrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT p.Id) as post_count,
        COUNT(DISTINCT b.Id) as badge_count,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as question_score,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as answer_score,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as rep_rank,
        DENSE_RANK() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY COUNT(DISTINCT p.Id) DESC) as yearly_activity_rank
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT OUTER JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 100
        AND u.CreationDate >= TIMESTAMP '2015-01-01'
        AND (u.Location IS NULL OR LENGTH(TRIM(u.Location)) > 0)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) > 5
),
post_engagement_stats AS (
    SELECT 
        p.Id as post_id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        COALESCE(p.CommentCount, 0) as comment_count,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) as upvote_count,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) as downvote_count,
        COUNT(DISTINCT pl.Id) FILTER (WHERE pl.LinkTypeId = 1) as linked_count,
        AVG(EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate))/3600.0) OVER (
            PARTITION BY p.OwnerUserId 
            ORDER BY p.CreationDate 
            ROWS BETWEEN 10 PRECEDING AND CURRENT ROW
        ) as avg_activity_hours,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) - p.Score as score_diff_next,
        STRING_AGG(DISTINCT SUBSTRING(t.TagName, 1, 20), ', ') FILTER (
            WHERE t.Count > 1000
        ) OVER (PARTITION BY p.OwnerUserId) as popular_tags
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.CreationDate > TIMESTAMP '2018-01-01'
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    LEFT JOIN LATERAL (
        SELECT UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as tag_name
    ) pt ON TRUE
    LEFT JOIN Tags t ON pt.tag_name = t.TagName
    WHERE p.CreationDate BETWEEN TIMESTAMP '2018-01-01' AND TIMESTAMP '2023-12-31'
        AND p.Body IS NOT NULL
        AND LENGTH(p.Body) > 100
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.Score, p.ViewCount, 
             p.CommentCount, p.CreationDate, p.LastActivityDate
),
correlated_influence AS (
    SELECT 
        uam.Id,
        uam.DisplayName,
        uam.rep_rank,
        CASE 
            WHEN uam.Reputation > 10000 THEN 'Elite'
            WHEN uam.Reputation > 5000 THEN 'Advanced'
            WHEN uam.Reputation > 1000 THEN 'Intermediate'
            ELSE 'Beginner'
        END as user_tier,
        (SELECT COUNT(*)
         FROM Posts p2
         WHERE p2.OwnerUserId = uam.Id
           AND p2.AcceptedAnswerId IS NOT NULL
           AND EXISTS (
               SELECT 1 FROM Comments c 
               WHERE c.PostId = p2.Id 
                 AND c.Score > 3
           )
        ) as accepted_with_quality_comments,
        (SELECT COALESCE(SUM(ph.PostId), 0)
         FROM PostHistory ph
         WHERE ph.UserId = uam.Id
           AND ph.PostHistoryTypeId IN (4, 5, 6)
           AND ph.CreationDate > (SELECT MAX(p.CreationDate) 
                                  FROM Posts p 
                                  WHERE p.OwnerUserId = uam.Id) - INTERVAL '90 days'
        ) as recent_edit_activity_sum
    FROM user_activity_metrics uam
    WHERE uam.post_count > (
        SELECT AVG(post_count) * 1.5 
        FROM user_activity_metrics
    )
)
SELECT 
    ci.DisplayName,
    ci.user_tier,
    ci.rep_rank,
    COALESCE(NULLIF(ROUND(AVG(pes.Score)::numeric, 2), 0), -1) as avg_post_score,
    COALESCE(SUM(pes.upvote_count)::bigint, 0) as total_upvotes,
    COALESCE(SUM(pes.downvote_count)::bigint, 0) as total_downvotes,
    ROUND(AVG(COALESCE(pes.avg_activity_hours, 0))::numeric, 2) as avg_engagement_hours,
    MAX(pes.ViewCount) as max_views,
    COUNT(DISTINCT CASE WHEN pes.score_diff_next > 10 THEN pes.post_id END) as improving_posts_count,
    ci.accepted_with_quality_comments,
    SUBSTRING(COALESCE(MAX(pes.popular_tags), 'none'), 1, 100) as top_tags,
    CASE 
        WHEN ci.recent_edit_activity_sum > 1000 THEN 'Highly Active Editor'
        WHEN ci.recent_edit_activity_sum > 100 THEN 'Active Editor'
        ELSE 'Passive'
    END as editing_profile
FROM correlated_influence ci
INNER JOIN post_engagement_stats pes ON ci.Id = pes.OwnerUserId
WHERE pes.post_id IN (
    SELECT p.Id 
    FROM Posts p
    WHERE p.Score > 0
    UNION
    SELECT p.ParentId
    FROM Posts p
    WHERE p.PostTypeId = 2 AND p.Score > 5
)
    AND (pes.comment_count > 0 OR pes.linked_count > 0)
    AND pes.ViewCount > (SELECT PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY ViewCount) 
                         FROM Posts WHERE ViewCount IS NOT NULL)
GROUP BY ci.Id, ci.DisplayName, ci.user_tier, ci.rep_rank, ci.accepted_with_quality_comments, ci.recent_edit_activity_sum
HAVING COUNT(DISTINCT pes.post_id) >= 3
    AND SUM(pes.upvote_count) > SUM(pes.downvote_count) * 2
ORDER BY 
    CASE ci.user_tier
        WHEN 'Elite' THEN 1
        WHEN 'Advanced' THEN 2
        WHEN 'Intermediate' THEN 3
        ELSE 4
    END,
    avg_post_score DESC NULLS LAST,
    total_upvotes DESC
LIMIT 500;
