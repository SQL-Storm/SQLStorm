-- {"query": "5641.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 549} 
WITH
recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Question
    AND p.CreationDate >= NOW() - INTERVAL '30 days'
),
tag_cluster AS (
  SELECT
    t.TagName,
    COUNT(*) AS tag_count
  FROM Tags t
  GROUP BY t.TagName
),
complex_agg AS (
  SELECT
    q.PostId,
    q.Title,
    q.Tags,
    q.CreationDate,
    q.ViewCount,
    q.Score,
    q.AnswerCount,
    q.CommentCount,
    q.FavoriteCount,
    COALESCE(u.DisplayName, q.OwnerDisplayName) AS OwnerName,
    u.Reputation,
    (SELECT AVG( v.BountyAmount ) FROM Votes v WHERE v.PostId = q.PostId AND v.BountyAmount > 0) AS AvgBounty
  FROM recent_questions q
  LEFT JOIN Users u ON q.OwnerUserId = u.Id
),
window_calc AS (
  SELECT
    ca.*,
    ROW_NUMBER() OVER (PARTITION BY ca.OwnerName ORDER BY ca.CreationDate DESC) AS rn_owner,
    DENSE_RANK() OVER (ORDER BY ca.ViewCount DESC, ca.Score DESC) AS view_score_rank
  FROM complex_agg ca
),
filtered AS (
  SELECT *
  FROM window_calc
  WHERE rn_owner = 1
    AND view_score_rank <= 100
)
SELECT
  f.PostId,
  f.Title,
  f.Tags,
  f.CreationDate,
  f.ViewCount,
  f.Score,
  f.AnswerCount,
  f.CommentCount,
  f.FavoriteCount,
  f.OwnerName,
  f.Reputation,
  f.AvgBounty,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = f.PostId AND pl.LinkTypeId = 3) AS DuplicateLinks,
  (SELECT STRING_AGG( tl.Name, ', ' ) FROM PostLinks pl2
     JOIN Tags t ON t.Id = (SELECT TagName FROM Tags WHERE Id = t.Id LIMIT 1)
     WHERE pl2.PostId = f.PostId AND pl2.LinkTypeId = 1) AS LinkedTags
FROM filtered f
ORDER BY f.CreationDate DESC
LIMIT 100;