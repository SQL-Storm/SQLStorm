-- {"query": "16048.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 114415, "output_tokens": 106076} 

WITH user_activity_metrics AS (
  SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT p.Id) as post_count,
    COUNT(DISTINCT v.Id) as vote_count,
    COUNT(DISTINCT b.Id) as badge_count,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) as avg_question_score,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END), 0) as total_bounties_offered,
    DENSE_RANK() OVER (ORDER BY u.Reputation DESC) as reputation_rank
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId
  LEFT JOIN Votes v ON u.Id = v.UserId
  LEFT JOIN Badges b ON u.Id = b.UserId
  WHERE u.CreationDate >= TIMESTAMP '2020-01-01'
    AND (u.Location IS NULL OR LENGTH(TRIM(u.Location)) > 0)
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
  HAVING COUNT(DISTINCT p.Id) > 5
),
post_engagement_stats AS (
  SELECT
    p.Id as post_id,
    p.Title,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.OwnerUserId,
    pt.Name as post_type_name,
    COALESCE(p.Score, 0) * 1.0 / NULLIF(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - p.CreationDate)) / 86400.0, 0) as score_velocity,
    COUNT(DISTINCT c.Id) OVER (PARTITION BY p.Id) as total_comments,
    COUNT(DISTINCT pl.Id) OVER (PARTITION BY p.Id) as link_count,
    STRING_AGG(DISTINCT SUBSTRING(COALESCE(c.Text, ''), 1, 50), ' | ') OVER (PARTITION BY p.Id) as comment_preview,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC NULLS LAST) as user_post_rank
  FROM Posts p
  INNER JOIN PostTypes pt ON p.PostTypeId = pt.Id
  LEFT JOIN Comments c ON p.Id = c.PostId
  LEFT JOIN PostLinks pl ON p.Id = pl.PostId
  WHERE p.CreationDate >= TIMESTAMP '2019-01-01'
    AND p.PostTypeId IN (1, 2)
    AND (p.ClosedDate IS NULL OR p.ClosedDate > TIMESTAMP '2022-01-01')
),
tag_expertise AS (
  SELECT 
    u.Id as user_id,
    tag_elem as tag_name,
    COUNT(*) as tag_usage_count,
    AVG(p.Score) as avg_tag_score,
    RANK() OVER (PARTITION BY u.Id ORDER BY COUNT(*) DESC) as tag_rank_for_user
  FROM Users u
  INNER JOIN Posts p ON u.Id = p.OwnerUserId
  CROSS JOIN LATERAL unnest(string_to_array(NULLIF(substring(p.Tags, 2, length(COALESCE(p.Tags, '')) - 2), ''), '><')) as tag_elem
  WHERE p.PostTypeId = 1 
    AND p.Tags IS NOT NULL
    AND LENGTH(p.Tags) > 2
  GROUP BY u.Id, tag_elem
  HAVING COUNT(*) >= 3
),
answer_acceptance_rates AS (
  SELECT
    q.OwnerUserId as question_owner_id,
    COUNT(DISTINCT q.Id) as questions_asked,
    COUNT(DISTINCT CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN q.Id END) as questions_with_accepted_answer,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN q.Id END) / 
          NULLIF(COUNT(DISTINCT q.Id), 0), 2) as acceptance_rate,
    AVG(EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate)) / 3600.0) as avg_hours_to_acceptance
  FROM Posts q
  LEFT JOIN Posts a ON q.AcceptedAnswerId = a.Id
  WHERE q.PostTypeId = 1
  GROUP BY q.OwnerUserId
)
SELECT 
  uam.DisplayName,
  COALESCE(uam.Location, 'Unknown') as location,
  uam.Reputation,
  uam.reputation_rank,
  uam.post_count,
  uam.vote_count,
  uam.badge_count,
  ROUND(CAST(uam.avg_question_score AS NUMERIC), 2) as avg_question_score,
  uam.total_bounties_offered,
  pes.Title as top_post_title,
  pes.Score as top_post_score,
  COALESCE(pes.ViewCount, 0) as top_post_views,
  ROUND(CAST(pes.score_velocity AS NUMERIC), 4) as top_post_score_velocity,
  pes.total_comments,
  pes.link_count,
  te.tag_name as primary_tag,
  te.tag_usage_count,
  ROUND(CAST(te.avg_tag_score AS NUMERIC), 2) as avg_tag_score,
  aar.questions_asked,
  aar.acceptance_rate,
  ROUND(CAST(aar.avg_hours_to_acceptance AS NUMERIC), 2) as avg_hours_to_acceptance,
  CASE 
    WHEN uam.Reputation > 10000 AND aar.acceptance_rate > 75 THEN 'Elite'
    WHEN uam.Reputation > 5000 AND aar.acceptance_rate > 50 THEN 'Advanced'
    WHEN uam.Reputation > 1000 THEN 'Intermediate'
    ELSE 'Beginner'
  END as user_tier,
  (SELECT COUNT(*) FROM Votes v2 
   WHERE v2.UserId = uam.Id 
     AND v2.VoteTypeId = 2 
     AND v2.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '90 days') as recent_upvotes_given,
  EXISTS(SELECT 1 FROM Badges b2 
         WHERE b2.UserId = uam.Id 
           AND b2.Class = 1 
           AND b2.TagBased = 1) as has_gold_tag_badge
FROM user_activity_metrics uam
INNER JOIN post_engagement_stats pes ON uam.Id = pes.OwnerUserId AND pes.user_post_rank = 1
LEFT OUTER JOIN tag_expertise te ON uam.Id = te.user_id AND te.tag_rank_for_user = 1
LEFT OUTER JOIN answer_acceptance_rates aar ON uam.Id = aar.question_owner_id
WHERE uam.reputation_rank <= 5000
  AND (pes.Score > 10 OR pes.ViewCount > 1000)
  AND NOT EXISTS (
    SELECT 1 FROM Posts p2 
    WHERE p2.OwnerUserId = uam.Id 
      AND p2.ClosedDate IS NOT NULL 
      AND p2.Score < -5
  )
ORDER BY 
  CASE WHEN aar.acceptance_rate IS NULL THEN 1 ELSE 0 END,
  uam.Reputation DESC,
  pes.score_velocity DESC NULLS LAST,
  te.tag_usage_count DESC NULLS LAST
LIMIT 100;
