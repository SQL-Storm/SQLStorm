-- {"query": "16071.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 2167}

WITH user_activity_metrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.Location, 'Unknown') AS Location,
        COUNT(DISTINCT p.Id) AS post_count,
        COUNT(DISTINCT b.Id) AS badge_count,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS avg_question_score,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS total_bounties_offered,
        ROW_NUMBER() OVER (PARTITION BY SUBSTRING(COALESCE(u.Location, 'Unknown'), 1, 20) ORDER BY u.Reputation DESC) AS location_rank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT b.Id) DESC) AS global_badge_rank
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId AND p.CreationDate >= u.CreationDate + INTERVAL '30 days'
    LEFT OUTER JOIN Badges b ON u.Id = b.UserId AND b.Class IN (1, 2)
    LEFT OUTER JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId = 8
    WHERE u.Reputation > 1000 
        AND u.CreationDate >= '2020-01-01'
        AND (u.LastAccessDate IS NULL OR u.LastAccessDate >= '2023-01-01')
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
    HAVING COUNT(DISTINCT p.Id) > 5
),
post_engagement_stats AS (
    SELECT 
        p.Id AS post_id,
        p.OwnerUserId,
        p.Title,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        LENGTH(COALESCE(p.Body, '')) AS body_length,
        CASE 
            WHEN p.Tags IS NOT NULL THEN array_length(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), 1)
            ELSE 0 
        END AS tag_count,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0) AS positive_comments,
        (SELECT AVG(ph.CreationDate - p.CreationDate) 
         FROM PostHistory ph 
         WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6)) AS avg_edit_delay,
        COALESCE(p.AnswerCount, 0) AS answer_count,
        EXISTS(SELECT 1 FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS is_duplicate,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_post_score,
        LEAD(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) - p.CreationDate AS time_to_next_post
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
        AND p.CreationDate >= '2021-01-01'
        AND p.Score IS NOT NULL
        AND (p.ClosedDate IS NULL OR p.ClosedDate > p.CreationDate + INTERVAL '7 days')
),
complex_aggregation AS (
    SELECT 
        uam.Id AS user_id,
        uam.DisplayName,
        uam.Location,
        uam.location_rank,
        uam.post_count,
        uam.badge_count,
        ROUND(uam.avg_question_score::numeric, 2) AS avg_q_score,
        uam.total_bounties_offered,
        COUNT(DISTINCT pes.post_id) FILTER (WHERE pes.PostTypeId = 1 AND pes.Score > 10) AS high_quality_questions,
        COUNT(DISTINCT pes.post_id) FILTER (WHERE pes.is_duplicate = true) AS duplicate_posts,
        AVG(pes.ViewCount) FILTER (WHERE pes.ViewCount IS NOT NULL AND pes.ViewCount > 0) AS avg_views,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pes.body_length) AS median_body_length,
        MAX(pes.positive_comments) AS max_positive_comments,
        STRING_AGG(DISTINCT SUBSTRING(pes.Title, 1, 30), ' | ' ORDER BY SUBSTRING(pes.Title, 1, 30)) FILTER (WHERE pes.Score > 20) AS top_post_titles,
        CASE 
            WHEN AVG(EXTRACT(EPOCH FROM pes.time_to_next_post)) < 86400 THEN 'Very Active'
            WHEN AVG(EXTRACT(EPOCH FROM pes.time_to_next_post)) < 604800 THEN 'Active'
            WHEN AVG(EXTRACT(EPOCH FROM pes.time_to_next_post)) < 2592000 THEN 'Moderate'
            ELSE 'Occasional'
        END AS activity_level,
        SUM(CASE WHEN pes.prev_post_score IS NOT NULL AND pes.Score > pes.prev_post_score THEN 1 ELSE 0 END)::float / 
            NULLIF(COUNT(pes.prev_post_score) FILTER (WHERE pes.prev_post_score IS NOT NULL), 0) AS improvement_ratio
    FROM user_activity_metrics uam
    INNER JOIN post_engagement_stats pes ON uam.Id = pes.OwnerUserId
    WHERE pes.body_length > 100
    GROUP BY uam.Id, uam.DisplayName, uam.Location, uam.location_rank, uam.post_count, 
             uam.badge_count, uam.avg_question_score, uam.total_bounties_offered
)
SELECT 
    ca.user_id,
    ca.DisplayName,
    ca.Location,
    ca.location_rank,
    ca.post_count,
    ca.badge_count,
    ca.avg_q_score,
    ca.total_bounties_offered,
    ca.high_quality_questions,
    ca.duplicate_posts,
    ROUND(ca.avg_views::numeric, 2) AS avg_views,
    ca.median_body_length,
    ca.max_positive_comments,
    ca.activity_level,
    ROUND(COALESCE(ca.improvement_ratio, 0)::numeric, 3) AS improvement_ratio,
    ca.top_post_titles,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = ca.user_id AND v.VoteTypeId = 2) AS total_upvotes_cast,
    (SELECT COUNT(DISTINCT t.Id) 
     FROM Tags t 
     INNER JOIN Posts p ON '><' || t.TagName || '><' LIKE '%' || SUBSTRING(p.Tags, 1, 50) || '%'
     WHERE p.OwnerUserId = ca.user_id) AS unique_tags_used,
    CASE 
        WHEN ca.badge_count > 50 AND ca.high_quality_questions > 20 THEN 'Elite Contributor'
        WHEN ca.badge_count > 20 AND ca.high_quality_questions > 10 THEN 'Advanced Contributor'
        WHEN ca.badge_count > 5 OR ca.high_quality_questions > 5 THEN 'Regular Contributor'
        ELSE 'Casual Contributor'
    END AS contributor_tier
FROM complex_aggregation ca
WHERE ca.high_quality_questions >= 3
    AND ca.avg_views > (SELECT AVG(avg_views) * 0.8 FROM complex_aggregation WHERE avg_views IS NOT NULL)
    AND NOT EXISTS (
        SELECT 1 FROM Votes v 
        WHERE v.UserId = ca.user_id 
        AND v.VoteTypeId IN (4, 12) 
        GROUP BY v.UserId 
        HAVING COUNT(*) > 10
    )
ORDER BY 
    ca.badge_count DESC,
    ca.high_quality_questions DESC,
    COALESCE(ca.improvement_ratio, 0) DESC
LIMIT 100;
