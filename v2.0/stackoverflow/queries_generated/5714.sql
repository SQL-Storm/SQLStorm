-- {"query": "5714.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 677} 
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.CommentCount,
    p.AnswerCount,
    p.LastActivityDate,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.Country AS Dummy  -- placeholder to keep schema variety if needed
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 -- questions
    AND p.CreationDate >= NOW() - INTERVAL '180 days'
),
tag_stats AS (
  SELECT
    unnest(string_to_array(substr(t.Tags, 2, length(t.Tags)-2), '><')) AS tag,
    count(*) AS question_count,
    avg(p.Score) AS avg_score,
    max(p.ViewCount) AS max_views
  FROM Posts p
  JOIN Tags t ON p.Id = t.Id
  WHERE p.PostTypeId = 1
  GROUP BY 1
),
top_tags AS (
  SELECT tag, question_count, avg_score, max_views
  FROM tag_stats
  ORDER BY question_count DESC, avg_score DESC
  LIMIT 10
),
complex_derived AS (
  SELECT
    q.PostId,
    q.Title,
    q.CreationDate,
    q.Views,
    q.Score,
    q.OwnerUserId,
    q.OwnerDisplayName,
    -- correlated subquery: count comments on the question
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.PostId) AS CommentCountForPost,
    -- window function over recent questions by creation date
    ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.CreationDate DESC) AS rn_by_author
  FROM recent_questions q
),
mixed_aggregate AS (
  SELECT
    c.PostId,
    c.Title,
    c.CreationDate,
    c.CommentCountForPost,
    c.Score,
    c.OwnerUserId,
    c.OwnerDisplayName,
    c.rn_by_author,
    -- complex predicate: score-weighted flag
    CASE
      WHEN c.Score >= 10 THEN 'high'
      WHEN c.Score >= 0 THEN 'medium'
      ELSE 'low'
    END AS score_tier,
    -- compute a string expression
    CONCAT('[', c.OwnerDisplayName, '] ', c.Title) AS TitleWithOwner
  FROM complex_derived c
),
final_result AS (
  SELECT
    m.PostId,
    m.Title,
    m.CreationDate,
    m.CommentCountForPost,
    m.Score,
    m.OwnerUserId,
    m.OwnerDisplayName,
    m.score_tier,
    m.TitleWithOwner,
    -- left join to top_tags to enrich with tag context
    t.tag AS top_tag,
    t.question_count AS top_tag_question_count
  FROM mixed_aggregate m
  LEFT JOIN top_tags t ON POSITION(t.tag IN m.Title) > 0
  ORDER BY m.CreationDate DESC
  LIMIT 100
)
SELECT
  *
FROM final_result
ORDER BY CreationDate DESC;