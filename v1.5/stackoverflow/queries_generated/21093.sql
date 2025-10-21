-- {"query": "21093.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2168, "output_tokens": 1314} 

WITH active_users AS (
    SELECT u.Id, u.DisplayName, u.Reputation,
           COUNT(DISTINCT p.Id) AS total_posts,
           SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS question_count,
           SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS answer_count
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.CreationDate > NOW() - INTERVAL '1 year'
    WHERE u.Reputation > 100 AND u.LastAccessDate > NOW() - INTERVAL '30 days'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 0
),
user_activity AS (
    SELECT au.Id,
           au.total_posts,
           au.question_count,
           au.answer_count,
           au.Reputation,
           COUNT(DISTINCT v.PostId) AS upvoted_posts,
           SUM(v.BountyAmount) AS total_bounties_given,
           AVG(DATE_PART('day', p.CreationDate - u.CreationDate)) OVER (PARTITION BY au.Id) AS avg_posting_frequency_days,
           STRING_AGG(DISTINCT COALESCE(b.Name, 'No Badge'), '; ') AS badges_earned,
           MAX(CASE WHEN b.Class = 1 THEN b.Date ELSE NULL END) AS last_gold_badge_date
    FROM active_users au
    LEFT JOIN Votes v ON au.Id = v.UserId AND v.VoteTypeId IN (2, 8)  -- Upvotes and Bounty starts
    LEFT JOIN Posts p ON v.PostId = p.Id
    LEFT JOIN Badges b ON au.Id = b.UserId
    LEFT JOIN Users u ON au.Id = u.Id
    GROUP BY au.Id, au.total_posts, au.question_count, au.answer_count, au.Reputation
),
post_engagement AS (
    SELECT p.Id AS post_id,
           p.OwnerUserId,
           p.Score,
           p.ViewCount,
           p.AnswerCount,
           p.CommentCount,
           p.FavoriteCount,
           p.ClosedDate,
           COALESCE(ph.Comment, '') AS close_reason_comment,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC, p.Score DESC) AS engagement_rank,
           LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS prev_post_score
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId 
        AND ph.PostHistoryTypeId = 10  -- Post Closed
        AND ph.CreationDate = (SELECT MAX(ph2.CreationDate) FROM PostHistory ph2 WHERE ph2.PostId = p.Id AND ph2.PostHistoryTypeId = 10)
    WHERE p.PostTypeId = 1  -- Questions only
      AND p.Score > 0
      AND (p.ClosedDate IS NULL OR p.ClosedDate > NOW() - INTERVAL '6 months')
),
linked_posts AS (
    SELECT pl.PostId,
           COUNT(DISTINCT pl.RelatedPostId) AS link_count,
           SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS duplicate_links
    FROM PostLinks pl
    WHERE pl.CreationDate > NOW() - INTERVAL '1 year'
    GROUP BY pl.PostId
)
SELECT 
    ua.DisplayName AS user_name,
    ua.Reputation,
    ua.total_posts,
    ua.question_count,
    ua.answer_count,
    COALESCE(pe.engagement_rank, 999) AS top_post_rank,
    COALESCE(pe.ViewCount, 0) AS top_post_views,
    COALESCE(pe.AnswerCount, 0) AS top_post_answers,
    COALESCE(lp.link_count, 0) AS outbound_links,
    COALESCE(lp.duplicate_links, 0) AS duplicate_indicators,
    ua.upvoted_posts,
    ua.total_bounties_given,
    ua.badges_earned,
    CASE 
        WHEN ua.last_gold_badge_date IS NOT NULL AND ua.last_gold_badge_date > NOW() - INTERVAL '3 months' THEN 'Recent Gold Earner'
        WHEN ua.question_count > 10 AND ua.answer_count > 5 THEN 'Active Questioner & Answerer'
        WHEN ua.total_posts > 50 AND pe.top_post_rank <= 10 THEN 'High Impact Poster'
        ELSE 'Emerging Contributor'
    END AS contributor_tier,
    -- Complex string manipulation for tags analysis
    (SELECT STRING_AGG(DISTINCT UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')), ', ')
     FROM Posts p2 
     WHERE p2.OwnerUserId = ua.Id AND p2.PostTypeId = 1 
     LIMIT 5) AS top_user_tags,
    -- NULL-aware calculation for engagement score
    GREATEST(
        COALESCE(pe.Score * 1.5, 0) + 
        COALESCE(pe.ViewCount / 100.0, 0) + 
        COALESCE(pe.AnswerCount * 2, 0) + 
        COALESCE(ua.upvoted_posts * 0.5, 0) +
        CASE WHEN pe.ClosedDate IS NOT NULL THEN -10 ELSE 0 END,
        0
    ) AS engagement_score,
    -- Window function for percentile ranking
    PERCENT_RANK() OVER (ORDER BY COALESCE(pe.ViewCount, 0) DESC) * 100 AS view_percentile
FROM user_activity ua
LEFT JOIN post_engagement pe ON ua.Id = pe.OwnerUserId AND pe.engagement_rank = 1
LEFT JOIN linked_posts lp ON pe.post_id = lp.PostId
LEFT JOIN Comments c ON pe.post_id = c.PostId AND c.Score > 0
WHERE ua.question_count > 0 
  AND (ua.Reputation BETWEEN 100 AND 10000 OR ua.total_bounties_given > 0)
  AND (pe.top_post_rank <= 50 OR lp.link_count > 5)
  AND (COALESCE(ph.Comment, '') NOT LIKE '%spam%' OR ph.Comment IS NULL)
ORDER BY engagement_score DESC, ua.Reputation DESC
LIMIT 100;
