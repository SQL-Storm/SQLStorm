-- {"query": "5239.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 762} 
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.Body
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.CreationDate >= NOW() - INTERVAL '60 days'
),
top_tags AS (
  SELECT
    unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
  FROM Posts p
  WHERE p.Id IN (SELECT PostId FROM recent_questions)
  GROUP BY p.Id
),
tag_scores AS (
  SELECT
    t.tag,
    COUNT(*) AS question_count,
    SUM(p.Score) AS total_score,
    AVG(p.Score) AS avg_score
  FROM top_tags t
  JOIN Posts p ON p.Id IN (SELECT PostId FROM recent_questions) AND position('<' || t.tag || '>' IN p.Tags) > 0
  GROUP BY t.tag
),
ranked AS (
  SELECT
    tag,
    question_count,
    total_score,
    avg_score,
    ROW_NUMBER() OVER (ORDER BY total_score DESC, question_count DESC) AS rn
  FROM tag_scores
)
SELECT
  r.PostId,
  r.Title,
  r.Tags,
  r.CreationDate,
  r.Score AS PostScore,
  r.ViewCount,
  r.OwnerUserId,
  r.LastActivityDate,
  r.CommentCount,
  r.AnswerCount,
  r.FavoriteCount,
  COALESCE(u.Reputation, 0) AS OwnerReputation,
  u.DisplayName AS OwnerDisplayName,
  COALESCE(b.TotalBadges, 0) AS BadgeCount,
  STRING_AGG(DISTINCT t.tag, ',') FILTER (WHERE t.tag IS NOT NULL) AS TopTagsInPost,
  (SELECT STRING_AGG(CAST(v.BountyAmount AS varchar), ',') FROM Votes v WHERE v.PostId = r.PostId AND v.VoteTypeId = 8) AS ActiveBounties
FROM (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.Body
  FROM Posts p
  WHERE p.PostTypeId = 1
) r
LEFT JOIN Users u ON r.OwnerUserId = u.Id
LEFT JOIN (
  SELECT OwnerUserId, COUNT(*) AS TotalBadges
  FROM Badges
  GROUP BY OwnerUserId
) b ON r.OwnerUserId = b.OwnerUserId
LEFT JOIN (
  SELECT unnest(string_to_array(substr(r.Tags, 2, length(r.Tags)-2), '><')) AS tag
  FROM Posts r
  WHERE r.Id = r.PostId
) t ON TRUE
GROUP BY
  r.PostId,
  r.Title,
  r.Tags,
  r.CreationDate,
  r.Score,
  r.ViewCount,
  r.OwnerUserId,
  r.LastActivityDate,
  r.CommentCount,
  r.AnswerCount,
  r.FavoriteCount,
  u.Reputation,
  u.DisplayName,
  b.TotalBadges
ORDER BY r.LastActivityDate DESC
OFFSET 0 ROWS FETCH FIRST 100 ROWS ONLY;