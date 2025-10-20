-- {"query": "51069.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2129, "output_tokens": 999} 

WITH user_activity AS (
    SELECT 
        u.Id as user_id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as post_count,
        COUNT(DISTINCT CASE WHEN pt.Id = 1 THEN p.Id END) as question_count,
        COUNT(DISTINCT CASE WHEN pt.Id = 2 THEN p.Id END) as answer_count,
        SUM(COALESCE(v.BountyAmount, 0)) as total_bounties_offered,
        COUNT(DISTINCT CASE WHEN b.Id IS NOT NULL THEN b.Id END) as badge_count,
        AVG(p.Score) as avg_post_score,
        COUNT(DISTINCT pl.RelatedPostId) as link_count
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2)
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId = 8
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
top_users AS (
    SELECT 
        user_id,
        DisplayName,
        Reputation,
        post_count,
        question_count,
        answer_count,
        total_bounties_offered,
        badge_count,
        avg_post_score,
        link_count,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, post_count DESC) as rep_rank,
        ROW_NUMBER() OVER (ORDER BY post_count DESC, Reputation DESC) as activity_rank,
        NTILE(10) OVER (ORDER BY Reputation DESC) as reputation_decile
    FROM user_activity
    WHERE post_count > 0
),
monthly_stats AS (
    SELECT 
        DATE_TRUNC('month', p.CreationDate) as month,
        pt.Name as post_type,
        COUNT(p.Id) as total_posts,
        AVG(p.Score) as avg_score,
        SUM(p.ViewCount) as total_views,
        COUNT(DISTINCT p.OwnerUserId) as active_users
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.CreationDate >= NOW() - INTERVAL '12 months'
    GROUP BY DATE_TRUNC('month', p.CreationDate), pt.Name
)
SELECT 
    tu.DisplayName,
    tu.Reputation,
    tu.post_count,
    tu.question_count,
    tu.answer_count,
    tu.badge_count,
    tu.avg_post_score,
    tu.total_bounties_offered,
    tu.reputation_decile,
    
    -- Time-based analysis
    COALESCE(ms.total_posts, 0) as recent_monthly_posts,
    COALESCE(ms.avg_score, 0) as recent_avg_score,
    
    -- Network analysis
    (SELECT COUNT(DISTINCT pl2.RelatedPostId) 
     FROM PostLinks pl2 
     WHERE pl2.RelatedPostId IN (
         SELECT p2.Id FROM Posts p2 WHERE p2.OwnerUserId = tu.user_id
     )) as inbound_links,
    
    -- Content analysis
    (SELECT AVG(LENGTH(p3.Body)) 
     FROM Posts p3 
     WHERE p3.OwnerUserId = tu.user_id 
     AND p3.PostTypeId = 1 
     AND p3.Body IS NOT NULL) as avg_question_length,
    
    -- Voting pattern
    (SELECT COUNT(v2.Id) 
     FROM Votes v2 
     WHERE v2.UserId = tu.user_id 
     AND v2.VoteTypeId IN (2, 3)) as total_votes_cast,
    
    -- Collaboration score (co-authored questions/answers)
    (SELECT COUNT(DISTINCT ph.Id) 
     FROM PostHistory ph 
     JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id 
     WHERE ph.UserId = tu.user_id 
     AND ph.PostId IN (
         SELECT p4.Id FROM Posts p4 
         WHERE p4.LastEditorUserId != p4.OwnerUserId
         AND p4.OwnerUserId = tu.user_id
     )
     AND pht.Id IN (4, 5, 6)) as collaborative_edits
    
FROM top_users tu
LEFT JOIN monthly_stats ms ON DATE_TRUNC('month', NOW()) = ms.month 
    AND ms.post_type IN ('Question', 'Answer')
WHERE tu.reputation_decile <= 5  -- Top 50% of users by reputation
  AND tu.post_count >= 10        -- Active posters only
  AND tu.activity_rank <= 1000   -- Top 1000 most active users
ORDER BY tu.reputation DESC, tu.post_count DESC
LIMIT 50;
