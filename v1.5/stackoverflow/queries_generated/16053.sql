-- {"query": "16053.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 126090, "output_tokens": 116433} 

WITH user_activity_metrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.Location,
        COUNT(DISTINCT p.Id) as post_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as question_count,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answer_count,
        AVG(p.Score) as avg_post_score,
        MAX(p.ViewCount) as max_views,
        STRING_AGG(DISTINCT COALESCE(SUBSTRING(u.Location, 1, 20), 'Unknown'), ', ') 
            OVER (PARTITION BY COALESCE(u.Location, 'NULL')) as location_cluster
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000 
        AND u.CreationDate >= '2015-01-01'::timestamp
        AND (u.Location IS NOT NULL OR u.Reputation > 5000)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
    HAVING COUNT(DISTINCT p.Id) > 5
),
ranked_posts AS (
    SELECT 
        p.Id as PostId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CreationDate,
        COALESCE(p.Title, 'No Title') as Title,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC NULLS LAST) as score_rank,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC NULLS LAST) as view_rank,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        LEAD(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as next_post_date,
        COUNT(*) OVER (PARTITION BY EXTRACT(YEAR FROM p.CreationDate), p.OwnerUserId) as posts_same_year,
        SUM(COALESCE(p.Score, 0)) OVER (PARTITION BY p.OwnerUserId 
            ORDER BY p.CreationDate 
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) as cumulative_score
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
        AND p.Score IS NOT NULL
        AND p.CreationDate >= '2016-01-01'::timestamp
),
badge_achievements AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) as gold_badges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) as silver_badges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) as bronze_badges,
        MAX(CASE WHEN b.TagBased = 1 THEN b.Name END) as top_tag_badge,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM b.Date)) as median_badge_time
    FROM Badges b
    WHERE b.Date >= '2015-01-01'::timestamp
    GROUP BY b.UserId
),
vote_patterns AS (
    SELECT 
        v.PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) as upvotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) as downvotes,
        COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) as favorites,
        COUNT(CASE WHEN v.VoteTypeId = 8 THEN 1 END) as bounties,
        SUM(COALESCE(v.BountyAmount, 0)) as total_bounty,
        CAST(COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS FLOAT) / 
            NULLIF(COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END), 0) as upvote_ratio
    FROM Votes v
    WHERE v.CreationDate >= '2016-01-01'::timestamp
    GROUP BY v.PostId
)
SELECT 
    uam.DisplayName,
    CASE 
        WHEN uam.Reputation >= 25000 THEN 'Elite'
        WHEN uam.Reputation >= 10000 THEN 'Expert'
        WHEN uam.Reputation >= 5000 THEN 'Advanced'
        ELSE 'Intermediate'
    END as reputation_tier,
    uam.post_count,
    uam.question_count,
    uam.answer_count,
    ROUND(uam.avg_post_score::numeric, 2) as avg_score,
    ba.gold_badges,
    ba.silver_badges,
    ba.bronze_badges,
    rp.Title as best_post_title,
    rp.Score as best_post_score,
    rp.ViewCount as best_post_views,
    rp.cumulative_score,
    vp.upvotes,
    vp.downvotes,
    COALESCE(ROUND(vp.upvote_ratio::numeric, 2), 0) as upvote_ratio,
    vp.total_bounty,
    (SELECT COUNT(*) 
     FROM Comments c 
     WHERE c.UserId = uam.Id 
        AND c.Score > 0
        AND LENGTH(c.Text) > 100) as quality_comments,
    (SELECT COUNT(DISTINCT pl.RelatedPostId)
     FROM Posts p2
     INNER JOIN PostLinks pl ON p2.Id = pl.PostId
     WHERE p2.OwnerUserId = uam.Id 
        AND pl.LinkTypeId = 1) as linked_posts,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM Posts p3
            WHERE p3.OwnerUserId = uam.Id 
                AND p3.AcceptedAnswerId IS NOT NULL
                AND p3.PostTypeId = 1
        ) THEN 'Has Accepted Answers'
        ELSE 'No Accepted Answers'
    END as acceptance_status,
    EXTRACT(DAYS FROM (rp.next_post_date - rp.CreationDate)) as days_to_next_post,
    COALESCE(uam.Location, 'Unknown') as user_location
FROM user_activity_metrics uam
INNER JOIN ranked_posts rp ON uam.Id = rp.OwnerUserId AND rp.score_rank = 1
LEFT OUTER JOIN badge_achievements ba ON uam.Id = ba.UserId
LEFT OUTER JOIN vote_patterns vp ON rp.PostId = vp.PostId
WHERE rp.cumulative_score > 100
    AND (ba.gold_badges > 0 OR ba.silver_badges > 2 OR uam.avg_post_score > 5)
    AND rp.view_rank <= 10000
    AND (vp.upvotes IS NULL OR vp.upvotes > vp.downvotes * 2)
ORDER BY 
    uam.Reputation DESC,
    rp.cumulative_score DESC,
    vp.total_bounty DESC NULLS LAST
LIMIT 100;
