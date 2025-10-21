-- {"query": "16037.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 1769}

WITH user_engagement_metrics AS (
  SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.Location,
    COUNT(DISTINCT p.Id) as post_count,
    COUNT(DISTINCT v.Id) as vote_count,
    COUNT(DISTINCT b.Id) as badge_count,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) as total_question_views,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) as avg_answer_score,
    DENSE_RANK() OVER (ORDER BY u.Reputation DESC) as rep_rank,
    ROW_NUMBER() OVER (PARTITION BY COALESCE(SUBSTRING(u.Location FROM 1 FOR POSITION(',' IN u.Location || ',') - 1), 'Unknown') ORDER BY u.Reputation DESC) as location_rank
  FROM Users u
  LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
  LEFT OUTER JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3)
  LEFT OUTER JOIN Badges b ON u.Id = b.UserId AND b.Class <= 2
  WHERE u.CreationDate >= '2020-01-01'::timestamp
    AND (u.Location IS NOT NULL OR u.Reputation > 1000)
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
  HAVING COUNT(DISTINCT p.Id) > 5
),
post_complexity_scores AS (
  SELECT 
    p.Id as post_id,
    p.OwnerUserId,
    p.Title,
    LENGTH(COALESCE(p.Body, '')) as body_length,
    p.Score,
    p.AnswerCount,
    p.CommentCount,
    COALESCE(ARRAY_LENGTH(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), 1), 0) as tag_count,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6)) as edit_count,
    (SELECT STRING_AGG(DISTINCT u2.DisplayName, ', ') 
     FROM Comments c 
     INNER JOIN Users u2 ON c.UserId = u2.Id 
     WHERE c.PostId = p.Id AND c.Score >= 3) as top_commenters,
    EXISTS(SELECT 1 FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) as is_duplicate,
    LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_post_score,
    LEAD(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) - p.CreationDate as time_to_next_post
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2)
    AND p.CreationDate >= '2019-01-01'::timestamp
    AND p.ClosedDate IS NULL
    AND (p.Score > 0 OR p.AnswerCount > 0)
),
tag_expertise AS (
  SELECT 
    u.Id as user_id,
    UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as tag_name,
    COUNT(*) as posts_in_tag,
    AVG(p.Score) as avg_tag_score,
    SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL AND p.AcceptedAnswerId IN (SELECT Id FROM Posts WHERE OwnerUserId = u.Id) THEN 1 ELSE 0 END) as accepted_answers_in_tag
  FROM Users u
  INNER JOIN Posts p ON u.Id = p.OwnerUserId
  WHERE p.PostTypeId = 1 
    AND p.Tags IS NOT NULL
    AND LENGTH(p.Tags) > 2
  GROUP BY u.Id, tag_name
  HAVING COUNT(*) >= 3 AND AVG(p.Score) >= 2
)
SELECT 
  uem.DisplayName,
  COALESCE(NULLIF(TRIM(uem.Location), ''), 'Not Specified') as user_location,
  uem.Reputation,
  uem.rep_rank,
  uem.post_count,
  uem.badge_count,
  ROUND(CAST(uem.avg_answer_score as numeric), 2) as avg_answer_score,
  pcs.Title as most_complex_post_title,
  pcs.body_length,
  pcs.tag_count,
  pcs.edit_count,
  COALESCE(pcs.top_commenters, 'No prominent commenters') as engagement_contributors,
  CASE 
    WHEN pcs.Score > 50 THEN 'Highly Popular'
    WHEN pcs.Score > 20 THEN 'Popular'
    WHEN pcs.Score > 5 THEN 'Moderately Popular'
    ELSE 'Standard'
  END as post_popularity_tier,
  EXTRACT(EPOCH FROM pcs.time_to_next_post) / 86400.0 as days_to_next_post,
  te.tag_name as specialty_tag,
  te.posts_in_tag as specialty_post_count,
  ROUND(CAST(te.avg_tag_score as numeric), 2) as specialty_avg_score,
  (SELECT COUNT(DISTINCT v2.Id) 
   FROM Votes v2 
   WHERE v2.PostId = pcs.post_id AND v2.VoteTypeId = 2) as upvote_count,
  (SELECT COUNT(*) 
   FROM PostHistory ph2 
   WHERE ph2.PostId = pcs.post_id 
   AND ph2.PostHistoryTypeId = 10 
   AND ph2.Comment IN ('101', '102', '103')) as modern_close_attempts
FROM user_engagement_metrics uem
INNER JOIN post_complexity_scores pcs ON uem.Id = pcs.OwnerUserId
LEFT OUTER JOIN tag_expertise te ON uem.Id = te.user_id 
  AND te.posts_in_tag = (SELECT MAX(te2.posts_in_tag) FROM tag_expertise te2 WHERE te2.user_id = uem.Id)
WHERE uem.location_rank <= 10
  AND pcs.body_length > 200
  AND (pcs.is_duplicate = FALSE OR pcs.Score > 10)
  AND COALESCE(pcs.prev_post_score, 0) >= -5
ORDER BY 
  uem.Reputation DESC,
  pcs.Score DESC,
  pcs.body_length DESC
LIMIT 100;
