-- {"query": "16034.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 81725, "output_tokens": 75678} 

WITH RECURSIVE user_reputation_tiers AS (
    SELECT 
        Id,
        DisplayName,
        Reputation,
        CreationDate,
        NTILE(10) OVER (ORDER BY Reputation DESC) AS rep_decile,
        CASE 
            WHEN Reputation >= 25000 THEN 'Elite'
            WHEN Reputation >= 10000 THEN 'Expert'
            WHEN Reputation >= 3000 THEN 'Established'
            WHEN Reputation >= 500 THEN 'Active'
            ELSE 'Beginner'
        END AS tier,
        LAG(Reputation, 1, 0) OVER (PARTITION BY EXTRACT(YEAR FROM CreationDate) ORDER BY Reputation DESC) AS next_higher_rep
    FROM Users
    WHERE Reputation > 100
),
post_metrics AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        COALESCE(p.Score, 0) * 10 + COALESCE(p.ViewCount, 0) / 100.0 + COALESCE(p.AnswerCount, 0) * 5 AS engagement_score,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS upvotes,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS downvotes,
        STRING_AGG(DISTINCT SUBSTRING(c.Text, 1, 50), ' | ' ORDER BY SUBSTRING(c.Text, 1, 50)) AS comment_preview,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC NULLS LAST, p.ViewCount DESC NULLS LAST) AS user_post_rank
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN Comments c ON p.Id = c.PostId AND c.Score > 3
    WHERE p.PostTypeId IN (1, 2)
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '5 years'
    GROUP BY p.Id, p.OwnerUserId, p.PostTypeId, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount
),
badge_stats AS (
    SELECT 
        UserId,
        COUNT(*) FILTER (WHERE Class = 1) AS gold_badges,
        COUNT(*) FILTER (WHERE Class = 2) AS silver_badges,
        COUNT(*) FILTER (WHERE Class = 3) AS bronze_badges,
        COUNT(DISTINCT Name) AS unique_badge_types,
        ARRAY_AGG(DISTINCT Name ORDER BY Name) FILTER (WHERE Class = 1) AS gold_badge_list
    FROM Badges
    GROUP BY UserId
),
answer_acceptance_rates AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS total_answers,
        COUNT(DISTINCT CASE WHEN parent.AcceptedAnswerId = p.Id THEN p.Id END) AS accepted_answers,
        ROUND(100.0 * COUNT(DISTINCT CASE WHEN parent.AcceptedAnswerId = p.Id THEN p.Id END) / 
              NULLIF(COUNT(DISTINCT p.Id), 0), 2) AS acceptance_rate,
        AVG(EXTRACT(EPOCH FROM (p.CreationDate - parent.CreationDate)) / 3600.0) FILTER (WHERE parent.AcceptedAnswerId = p.Id) AS avg_hours_to_acceptance
    FROM Posts p
    INNER JOIN Posts parent ON p.ParentId = parent.Id
    WHERE p.PostTypeId = 2
        AND parent.PostTypeId = 1
    GROUP BY p.OwnerUserId
)
SELECT 
    urt.DisplayName,
    urt.Reputation,
    urt.tier AS reputation_tier,
    urt.rep_decile,
    COALESCE(bs.gold_badges, 0) AS gold_badges,
    COALESCE(bs.silver_badges, 0) AS silver_badges,
    COALESCE(bs.bronze_badges, 0) AS bronze_badges,
    COALESCE(aar.acceptance_rate, 0) AS answer_acceptance_pct,
    COALESCE(aar.avg_hours_to_acceptance, 0) AS avg_hours_to_accept,
    pm.engagement_score,
    pm.upvotes - pm.downvotes AS net_votes,
    COALESCE(pm.comment_preview, 'No comments') AS top_comment_snippets,
    (SELECT COUNT(*) 
     FROM PostLinks pl 
     INNER JOIN Posts p2 ON pl.RelatedPostId = p2.Id
     WHERE pl.PostId = pm.Id AND pl.LinkTypeId = 3) AS duplicate_count,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM PostHistory ph 
            WHERE ph.PostId = pm.Id 
                AND ph.PostHistoryTypeId IN (10, 12) 
                AND ph.CreationDate > CURRENT_DATE - INTERVAL '1 year'
        ) THEN 'Recently Problematic'
        WHEN pm.Score > 50 AND pm.ViewCount > 10000 THEN 'Viral'
        WHEN pm.Score < -5 THEN 'Poorly Received'
        ELSE 'Normal'
    END AS post_status,
    DENSE_RANK() OVER (
        PARTITION BY urt.tier 
        ORDER BY pm.engagement_score DESC NULLS LAST
    ) AS tier_engagement_rank,
    PERCENT_RANK() OVER (ORDER BY urt.Reputation) AS reputation_percentile
FROM user_reputation_tiers urt
INNER JOIN post_metrics pm ON urt.Id = pm.OwnerUserId
LEFT OUTER JOIN badge_stats bs ON urt.Id = bs.UserId
LEFT OUTER JOIN answer_acceptance_rates aar ON urt.Id = aar.OwnerUserId
WHERE pm.user_post_rank <= 5
    AND (bs.gold_badges > 0 OR urt.Reputation > 5000)
    AND pm.engagement_score > (
        SELECT AVG(engagement_score) * 0.5
        FROM post_metrics
        WHERE OwnerUserId IS NOT NULL
    )
    AND NOT EXISTS (
        SELECT 1 
        FROM Votes v 
        WHERE v.PostId = pm.Id 
            AND v.VoteTypeId IN (4, 12)
    )
ORDER BY 
    CASE 
        WHEN urt.tier = 'Elite' THEN 1
        WHEN urt.tier = 'Expert' THEN 2
        ELSE 3
    END,
    pm.engagement_score DESC,
    urt.Reputation DESC
LIMIT 1000;
