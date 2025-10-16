WITH user_activity_metrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        EXTRACT(YEAR FROM u.CreationDate) AS join_year,
        COUNT(DISTINCT p.Id) AS post_count,
        COUNT(DISTINCT b.Id) AS badge_count,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS question_count,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS answer_count,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS avg_post_score,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY u.Reputation DESC) AS rep_rank_in_year,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT b.Id) DESC) AS badge_rank_overall
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= DATE '2010-01-01'
        AND u.Reputation > 100
        AND COALESCE(u.Location, '') NOT LIKE '%deleted%'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) > 5
),
top_posts_with_engagement AS (
    SELECT 
        p.Id AS post_id,
        p.Title,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        COALESCE(p.FavoriteCount, 0) AS favorite_count,
        (p.Score * 1.0 + COALESCE(p.ViewCount, 0) * 0.001 + COALESCE(p.AnswerCount, 0) * 5 + 
         COALESCE(p.CommentCount, 0) * 0.5 + COALESCE(p.FavoriteCount, 0) * 2) AS engagement_score,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_post_score,
        LEAD(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS next_post_score,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS user_total_posts,
        STRING_AGG(t.tag_name, ', ') AS post_tags
    FROM Posts p
    LEFT JOIN LATERAL (
        SELECT TRIM(tag) AS tag_name
        FROM (
            SELECT
                CASE WHEN p.Tags IS NULL THEN NULL
                     ELSE REGEXP_SPLIT_TO_TABLE(REPLACE(REPLACE(TRIM(p.Tags), '><', '|'), '<', '') , '\|')
                END AS tag
        ) s(tag)
        WHERE tag IS NOT NULL
    ) t ON TRUE
    WHERE p.PostTypeId IN (1, 2)
        AND p.CreationDate BETWEEN DATE '2015-01-01' AND DATE '2023-12-31'
        AND (p.Score >= 5 OR p.ViewCount > 1000)
    GROUP BY p.Id, p.Title, p.PostTypeId, p.OwnerUserId, p.Score, p.ViewCount, 
             p.AnswerCount, p.CommentCount, p.FavoriteCount, p.CreationDate, p.Tags
),
vote_patterns AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvote_count,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvote_count,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS favorite_count,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN 1 ELSE 0 END) AS bounty_start_count,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN COALESCE(v.BountyAmount, 0) ELSE 0 END) AS total_bounty_amount,
        AVG((EXTRACT(EPOCH FROM v.CreationDate) - EXTRACT(EPOCH FROM p.CreationDate)) / 3600.0) AS avg_hours_to_vote
    FROM Votes v
    INNER JOIN Posts p ON v.PostId = p.Id
    WHERE v.CreationDate >= DATE '2015-01-01'
    GROUP BY v.PostId
),
best_posts_per_user AS (
    SELECT tp.OwnerUserId, tp.post_id, tp.Title, tp.engagement_score, tp.post_tags
    FROM (
        SELECT *,
            ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY engagement_score DESC) AS rn
        FROM top_posts_with_engagement
    ) tp
    WHERE tp.rn = 1
)
SELECT 
    uam.DisplayName,
    uam.Reputation,
    uam.join_year,
    uam.post_count,
    uam.question_count,
    uam.answer_count,
    uam.badge_count,
    ROUND(CAST(uam.avg_post_score AS NUMERIC), 2) AS avg_post_score,
    uam.rep_rank_in_year,
    uam.badge_rank_overall,
    bp.Title AS best_post_title,
    bp.engagement_score,
    bp.post_tags,
    COALESCE(vp.upvote_count, 0) AS best_post_upvotes,
    COALESCE(vp.downvote_count, 0) AS best_post_downvotes,
    COALESCE(vp.total_bounty_amount, 0) AS best_post_bounties,
    ROUND(CAST(COALESCE(vp.avg_hours_to_vote, 0) AS NUMERIC), 2) AS avg_hours_to_vote,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = uam.Id AND c.Score > 0) AS helpful_comments,
    (SELECT COUNT(DISTINCT pl.RelatedPostId) 
     FROM PostLinks pl 
     INNER JOIN Posts p2 ON pl.PostId = p2.Id 
     WHERE p2.OwnerUserId = uam.Id AND pl.LinkTypeId = 1) AS posts_with_links,
    CASE 
        WHEN uam.avg_post_score > 10 AND uam.badge_count > 20 THEN 'Elite Contributor'
        WHEN uam.avg_post_score > 5 AND uam.badge_count > 10 THEN 'Active Contributor'
        WHEN uam.post_count > 50 THEN 'Regular Contributor'
        ELSE 'Casual Contributor'
    END AS contributor_tier,
    COALESCE(NULLIF(TRIM(SUBSTRING(uam.DisplayName FROM 1 FOR 1)), ''), 'U') ||
        CAST((uam.Id % 1000) AS VARCHAR) AS anonymized_id,
    uam.Id
FROM user_activity_metrics uam
LEFT JOIN best_posts_per_user bp ON bp.OwnerUserId = uam.Id
LEFT JOIN vote_patterns vp ON bp.post_id = vp.PostId
WHERE uam.rep_rank_in_year <= 100
    AND (uam.question_count > 0 OR uam.answer_count > 3)
    AND NOT EXISTS (
        SELECT 1 FROM Posts p 
        WHERE p.OwnerUserId = uam.Id 
            AND p.ClosedDate IS NOT NULL
        GROUP BY p.OwnerUserId
        HAVING COUNT(*) > 10
    )
ORDER BY 
    CASE WHEN uam.badge_rank_overall <= 50 THEN 0 ELSE 1 END,
    uam.Reputation DESC,
    bp.engagement_score DESC
LIMIT 500;