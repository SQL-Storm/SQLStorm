-- {"query": "17090.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 2122}

WITH user_activity AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as post_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as question_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answer_count,
        AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL) as avg_post_score,
        MAX(p.CreationDate) as last_post_date,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) as reputation_rank,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) FILTER (WHERE p.Score IS NOT NULL) as median_score
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
tag_expertise AS (
    SELECT 
        p.OwnerUserId,
        TRIM(BOTH '<>' FROM unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))) as tag,
        COUNT(*) as tag_usage_count,
        SUM(p.Score) as total_tag_score,
        STRING_AGG(DISTINCT COALESCE(p.Title, 'Untitled'), ' | ' ORDER BY p.Score DESC) FILTER (WHERE p.Score > 10) as top_posts
    FROM Posts p
    WHERE p.Tags IS NOT NULL 
        AND p.PostTypeId = 1
        AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, tag
),
badge_patterns AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) as gold_badges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) as silver_badges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) as bronze_badges,
        COUNT(DISTINCT b.Name) FILTER (WHERE b.TagBased = B'1') as unique_tag_badges,
        ARRAY_AGG(DISTINCT b.Name ORDER BY b.Date DESC) FILTER (WHERE b.Class = 1) as gold_badge_names,
        LAG(COUNT(*), 1, 0) OVER (PARTITION BY b.UserId ORDER BY DATE_TRUNC('month', b.Date)) as prev_month_badges
    FROM Badges b
    GROUP BY b.UserId, DATE_TRUNC('month', b.Date)
),
controversial_posts AS (
    SELECT 
        p.Id as PostId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        COALESCE(p.Score::NUMERIC / NULLIF(p.ViewCount, 0), 0) as score_per_view,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) as upvotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) as downvotes,
        EXISTS (
            SELECT 1 
            FROM PostHistory ph 
            WHERE ph.PostId = p.Id 
                AND ph.PostHistoryTypeId IN (10, 12)
                AND ph.CreationDate > p.CreationDate + INTERVAL '1 day'
        ) as was_closed_or_deleted,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'community_owned'
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'has_accepted'
            ELSE 'open'
        END as post_status
    FROM Posts p
    WHERE p.Score < 0 
        OR (p.Score > 0 AND EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3))
)
SELECT 
    ua.DisplayName,
    ua.Reputation,
    ua.reputation_rank,
    ua.post_count,
    ROUND(ua.avg_post_score::NUMERIC, 2) as avg_score,
    ua.median_score,
    COALESCE(ua.question_count, 0) || '/' || COALESCE(ua.answer_count, 0) as "Q/A_ratio",
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - ua.last_post_date))/86400 as days_since_last_post,
    COALESCE(bp.gold_badges, 0) || '/' || COALESCE(bp.silver_badges, 0) || '/' || COALESCE(bp.bronze_badges, 0) as "G/S/B_badges",
    SUBSTRING(ARRAY_TO_STRING(bp.gold_badge_names, ', '), 1, 100) as gold_badges_sample,
    te.tag,
    te.tag_usage_count,
    te.total_tag_score,
    CASE 
        WHEN te.total_tag_score >= 100 THEN 'Expert'
        WHEN te.total_tag_score >= 50 THEN 'Advanced'
        WHEN te.total_tag_score >= 10 THEN 'Intermediate'
        ELSE 'Beginner'
    END as tag_expertise_level,
    LEFT(te.top_posts, 200) as top_tag_posts_sample,
    COUNT(DISTINCT cp.PostId) as controversial_posts,
    SUM(CASE WHEN cp.was_closed_or_deleted THEN 1 ELSE 0 END) as posts_closed_deleted,
    ROUND(AVG(cp.score_per_view)::NUMERIC * 1000, 4) as avg_score_per_1000_views,
    CASE 
        WHEN ua.Reputation > 10000 AND bp.gold_badges > 5 THEN 'Elite'
        WHEN ua.Reputation > 5000 OR bp.gold_badges > 2 THEN 'Veteran'
        WHEN ua.Reputation > 1000 THEN 'Regular'
        ELSE 'Newcomer'
    END as user_tier,
    ROW_NUMBER() OVER (
        PARTITION BY te.tag 
        ORDER BY te.total_tag_score DESC, ua.Reputation DESC
    ) as tag_rank
FROM user_activity ua
LEFT JOIN LATERAL (
    SELECT * FROM badge_patterns bp 
    WHERE bp.UserId = ua.Id 
    ORDER BY bp.prev_month_badges DESC 
    LIMIT 1
) bp ON true
INNER JOIN tag_expertise te ON ua.Id = te.OwnerUserId
LEFT JOIN controversial_posts cp ON ua.Id = cp.OwnerUserId
WHERE ua.post_count > 0
    AND te.tag_usage_count >= 5
    AND (ua.Reputation > 1000 OR bp.gold_badges > 0 OR te.total_tag_score > 50)
    AND NOT EXISTS (
        SELECT 1 
        FROM Posts p2 
        WHERE p2.OwnerUserId = ua.Id 
            AND p2.Score < -5 
            AND p2.CreationDate > CURRENT_TIMESTAMP - INTERVAL '30 days'
    )
GROUP BY 
    ua.Id, ua.DisplayName, ua.Reputation, ua.reputation_rank, 
    ua.post_count, ua.avg_post_score, ua.median_score,
    ua.question_count, ua.answer_count, ua.last_post_date,
    bp.gold_badges, bp.silver_badges, bp.bronze_badges, bp.gold_badge_names,
    te.tag, te.tag_usage_count, te.total_tag_score, te.top_posts
HAVING COUNT(DISTINCT cp.PostId) < ua.post_count * 0.5
ORDER BY 
    ua.reputation_rank ASC,
    te.total_tag_score DESC,
    tag_rank ASC
LIMIT 100;
