-- {"query": "51031.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2129, "output_tokens": 1246} 

WITH popular_tags AS (
  SELECT t.TagName, COUNT(*) as tag_usage_count
  FROM Tags t
  JOIN Posts p ON position(',' || t.TagName || '<' IN p.Tags) > 0
  WHERE p.PostTypeId = 1 AND p.CreationDate > NOW() - INTERVAL '1 year'
  GROUP BY t.TagName
  HAVING COUNT(*) > 100
  ORDER BY tag_usage_count DESC
  LIMIT 10
),
active_users AS (
  SELECT u.Id, u.Reputation, u.UpVotes, u.DownVotes,
         AVG(p.Score) as avg_post_score,
         COUNT(DISTINCT ph.Id) as edit_count
  FROM Users u
  JOIN Posts p ON u.Id = p.OwnerUserId
  LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4,5,6)
  WHERE u.CreationDate > NOW() - INTERVAL '2 years' 
    AND u.Reputation >= 100
    AND p.PostTypeId IN (1,2)
    AND p.CreationDate > NOW() - INTERVAL '6 months'
  GROUP BY u.Id, u.Reputation, u.UpVotes, u.DownVotes
  HAVING COUNT(p.Id) >= 5
),
influential_posts AS (
  SELECT p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount,
         p.CreationDate, p.OwnerUserId,
         ROW_NUMBER() OVER (PARTITION BY EXTRACT(MONTH FROM p.CreationDate) ORDER BY p.ViewCount DESC) as monthly_rank
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate > NOW() - INTERVAL '1 year'
    AND p.Score > 10
),
user_engagement AS (
  SELECT au.Id as user_id,
         au.avg_post_score,
         COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId END) as upvotes_given,
         COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId END) as downvotes_given,
         COUNT(DISTINCT c.Id) as comments_made,
         AVG(EXTRACT(DAY FROM (c.CreationDate - p.CreationDate))) as avg_comment_delay_days
  FROM active_users au
  LEFT JOIN Votes v ON au.Id = v.UserId AND v.VoteTypeId IN (2,3) AND v.CreationDate > NOW() - INTERVAL '3 months'
  LEFT JOIN Comments c ON au.Id = c.UserId
  LEFT JOIN Posts p ON c.PostId = p.Id
  WHERE c.CreationDate > NOW() - INTERVAL '3 months'
  GROUP BY au.Id, au.avg_post_score
),
tag_collaboration AS (
  SELECT pt.TagName,
         COUNT(DISTINCT p.OwnerUserId) as unique_contributors,
         AVG(u.Reputation) as avg_contributor_reputation,
         COUNT(DISTINCT CASE WHEN ph.UserId IS NOT NULL THEN ph.UserId END) as unique_editors,
         SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) as gold_badges_for_tag
  FROM popular_tags pt
  JOIN Posts p ON position(',' || pt.TagName || '<' IN p.Tags) > 0
  JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4,5,6)
  LEFT JOIN Badges b ON u.Id = b.UserId AND b.TagBased = 1 AND position(pt.TagName IN b.Name) > 0
  WHERE p.PostTypeId = 1
    AND p.CreationDate > NOW() - INTERVAL '6 months'
  GROUP BY pt.TagName
)
SELECT 
  ue.user_id as user_id,
  u.DisplayName,
  u.Reputation,
  ue.upvotes_given,
  ue.downvotes_given,
  ue.comments_made,
  ue.avg_comment_delay_days,
  COALESCE(ue.avg_post_score, 0) as avg_post_quality,
  COUNT(DISTINCT ip.Id) as high_impact_posts_contributed,
  STRING_AGG(DISTINCT tc.TagName, ', ') as collaborated_tags,
  AVG(tc.avg_contributor_reputation) as avg_tag_collaboration_reputation,
  tc.gold_badges_for_tag as tag_expertise_level,
  RANK() OVER (ORDER BY 
    (ue.upvotes_given * 2 + ue.comments_made + COALESCE(ue.avg_post_score, 0) * 10) DESC
  ) as community_influence_rank
FROM user_engagement ue
JOIN Users u ON ue.user_id = u.Id
LEFT JOIN influential_posts ip ON ue.user_id = ip.OwnerUserId AND ip.monthly_rank <= 5
LEFT JOIN (
  SELECT p.OwnerUserId, STRING_AGG(tc.TagName, ',') as TagName, 
         AVG(tc.avg_contributor_reputation) as avg_contributor_reputation,
         SUM(tc.gold_badges_for_tag) as gold_badges_for_tag
  FROM Posts p
  JOIN popular_tags pt ON position(',' || pt.TagName || '<' IN p.Tags) > 0
  JOIN tag_collaboration tc ON pt.TagName = tc.TagName
  WHERE p.PostTypeId IN (1,2)
  GROUP BY p.OwnerUserId
) tc ON ue.user_id = tc.OwnerUserId
GROUP BY ue.user_id, u.DisplayName, u.Reputation, ue.upvotes_given, ue.downvotes_given, 
         ue.comments_made, ue.avg_comment_delay_days, ue.avg_post_score, tc.TagName, 
         tc.avg_contributor_reputation, tc.gold_badges_for_tag
HAVING COUNT(DISTINCT ip.Id) > 0 OR tc.TagName IS NOT NULL
ORDER BY community_influence_rank
LIMIT 50;
