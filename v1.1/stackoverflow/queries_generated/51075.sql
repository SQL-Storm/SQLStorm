-- {"query": "51075.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2129, "output_tokens": 1026} 

WITH top_users AS (
  SELECT 
    u.Id,
    u.Reputation,
    u.DisplayName,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as question_count,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as answer_count,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) as total_upvotes
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id 
    AND p.PostTypeId IN (1, 2) 
    AND p.CreationDate > CURRENT_TIMESTAMP - INTERVAL '5 years'
    AND p.DeletionDate IS NULL
  LEFT JOIN Votes v ON v.PostId = p.Id 
    AND v.VoteTypeId = 2 -- Upvotes
    AND v.CreationDate > CURRENT_TIMESTAMP - INTERVAL '5 years'
  WHERE u.Reputation > 1000
    AND u.CreationDate < CURRENT_TIMESTAMP - INTERVAL '1 year'
  GROUP BY u.Id, u.Reputation, u.DisplayName
  HAVING COUNT(DISTINCT p.Id) > 50
),
high_quality_posts AS (
  SELECT 
    p.Id as post_id,
    p.OwnerUserId,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.Title,
    STRING_AGG(DISTINCT t.TagName, ', ') as tags
  FROM Posts p
  LEFT JOIN (
    SELECT 
      UNNEST(STRING_TO_ARRAY(
        SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), 
        '><'
      )) as tag_name,
      p.Id
    FROM Posts p
    WHERE p.PostTypeId = 1 
      AND p.Tags IS NOT NULL
      AND LENGTH(p.Tags) > 2
  ) t ON t.Id = p.Id
  WHERE p.PostTypeId = 1 -- Questions only
    AND p.Score >= 10
    AND p.ViewCount > 1000
    AND p.AcceptedAnswerId IS NOT NULL
    AND p.CreationDate > CURRENT_TIMESTAMP - INTERVAL '2 years'
    AND p.ClosedDate IS NULL
  GROUP BY p.Id, p.OwnerUserId, p.PostTypeId, p.Score, p.ViewCount, 
           p.CreationDate, p.Title
),
active_tags AS (
  SELECT 
    t.TagName,
    t.Count,
    COUNT(DISTINCT hp.post_id) as recent_question_count,
    AVG(hp.Score) as avg_question_score,
    SUM(hp.ViewCount) as total_views
  FROM Tags t
  INNER JOIN high_quality_posts hp ON hp.tags LIKE '%' || t.TagName || '%'
  WHERE t.Count > 500
    AND t.ExcerptPostId IS NOT NULL
  GROUP BY t.TagName, t.Count
  HAVING COUNT(DISTINCT hp.post_id) > 25
),
user_tag_activity AS (
  SELECT 
    tu.Id as user_id,
    tu.DisplayName,
    at.TagName,
    COUNT(DISTINCT hp.post_id) as questions_in_tag,
    AVG(hp.Score) as avg_score_in_tag,
    SUM(CASE WHEN v.VoteTypeId = 2 AND v.UserId IS NULL THEN 1 ELSE 0 END) as anonymous_upvotes
  FROM top_users tu
  INNER JOIN high_quality_posts hp ON hp.OwnerUserId = tu.Id
  INNER JOIN active_tags at ON hp.tags LIKE '%' || at.TagName || '%'
  LEFT JOIN Votes v ON v.PostId = hp.post_id 
    AND v.VoteTypeId = 2
    AND v.CreationDate > CURRENT_TIMESTAMP - INTERVAL '1 year'
  GROUP BY tu.Id, tu.DisplayName, at.TagName
  HAVING COUNT(DISTINCT hp.post_id) > 5
)
SELECT 
  uta.user_id,
  tu.Reputation,
  tu.question_count,
  tu.answer_count,
  uta.TagName as top_tag,
  uta.questions_in_tag,
  uta.avg_score_in_tag,
  uta.anonymous_upvotes,
  RANK() OVER (
    PARTITION BY uta.TagName 
    ORDER BY uta.questions_in_tag DESC, uta.avg_score_in_tag DESC
  ) as tag_rank,
  ROW_NUMBER() OVER (
    ORDER BY tu.Reputation DESC, uta.questions_in_tag DESC
  ) as overall_rank,
  at.total_views as tag_popularity
FROM user_tag_activity uta
INNER JOIN top_users tu ON tu.Id = uta.user_id
INNER JOIN active_tags at ON at.TagName = uta.TagName
WHERE uta.avg_score_in_tag > (SELECT AVG(avg_question_score) FROM active_tags)
  AND tu.Reputation > 5000
ORDER BY overall_rank
LIMIT 100;
