-- {"query": "51064.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2129, "output_tokens": 749} 

WITH popular_tags AS (
  SELECT t.TagName, COUNT(*) as tag_usage
  FROM Tags t
  JOIN Posts p ON string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') @> ARRAY[t.TagName]
  WHERE p.PostTypeId = 1 AND p.CreationDate > CURRENT_DATE - INTERVAL '1 year'
  GROUP BY t.TagName
  HAVING COUNT(*) > 100
  ORDER BY tag_usage DESC
  LIMIT 20
),
active_users AS (
  SELECT u.Id, u.Reputation, u.UpVotes - u.DownVotes as net_votes
  FROM Users u
  WHERE u.CreationDate < CURRENT_DATE - INTERVAL '6 months'
  AND u.LastAccessDate > CURRENT_DATE - INTERVAL '1 month'
),
post_stats AS (
  SELECT 
    p.Id,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    pt.Name as post_type,
    u.Id as owner_id,
    COALESCE(au.Reputation, 0) as owner_reputation,
    COALESCE(b.total_badges, 0) as owner_badges
  FROM Posts p
  JOIN PostTypes pt ON p.PostTypeId = pt.Id
  LEFT JOIN active_users u ON p.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT UserId, COUNT(*) as total_badges
    FROM Badges
    GROUP BY UserId
  ) b ON u.Id = b.UserId
  WHERE p.PostTypeId = 1
  AND p.DeletionDate IS NULL
  AND p.CreationDate > CURRENT_DATE - INTERVAL '2 years'
),
aggregated_stats AS (
  SELECT 
    pt.TagName,
    COUNT(ps.Id) as total_questions,
    AVG(ps.Score) as avg_score,
    SUM(ps.ViewCount) as total_views,
    SUM(ps.AnswerCount) as total_answers,
    AVG(ps.owner_reputation) as avg_owner_reputation,
    SUM(CASE WHEN ps.Score > 50 THEN 1 ELSE 0 END) as high_score_count,
    MIN(ps.CreationDate) as earliest_question,
    MAX(ps.CreationDate) as latest_question
  FROM post_stats ps
  JOIN popular_tags pt ON string_to_array(substring(ps.Tags, 2, length(ps.Tags)-2), '><') @> ARRAY[pt.TagName]
  GROUP BY pt.TagName
)
SELECT 
  ast.TagName,
  ast.total_questions,
  ROUND(ast.avg_score::numeric, 2) as avg_score,
  ast.total_views,
  ast.total_answers,
  ROUND(ast.avg_owner_reputation::numeric, 0) as avg_owner_reputation,
  ast.high_score_count,
  EXTRACT(EPOCH FROM (ast.latest_question - ast.earliest_question))/86400 as days_active,
  ROUND((ast.high_score_count::float / ast.total_questions) * 100, 2) as high_score_percentage,
  (
    SELECT STRING_AGG(DISTINCT c.Text, ' | ' ORDER BY c.CreationDate DESC)
    FROM Comments c
    JOIN post_stats ps2 ON c.PostId = ps2.Id
    WHERE ps2.Tags LIKE '%' || ast.TagName || '%'
    AND c.Score > 5
    AND c.CreationDate > CURRENT_DATE - INTERVAL '6 months'
    LIMIT 5
  ) as top_comments_sample
FROM aggregated_stats ast
ORDER BY ast.total_views DESC, ast.avg_score DESC
LIMIT 15;
