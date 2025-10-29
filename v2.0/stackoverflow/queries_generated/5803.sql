-- {"query": "5803.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 852} 
WITH ranked_posts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.LastActivityDate,
    p.PostTypeId,
    COALESCE(p.AcceptedAnswerId, -1) AS AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.Location,
    u.CreationDate AS UserCreationDate,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC, p.LastActivityDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  LEFT JOIN Posts rl ON rl.Id = pl.RelatedPostId
  WHERE p.PostTypeId IN (1,2) -- Questions and Answers
    AND p.LastActivityDate IS NOT NULL
),
cte_stats AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.OwnerUserId,
    rp.OwnerDisplayName,
    rp.Reputation,
    rp.LastActivityDate,
    rp.Tags,
    rp.Body,
    rp.PostTypeId,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.PostId) AS CommentCountForPost,
    (SELECT STRING_AGG(vt.Name, ',') FROM Votes v JOIN VoteTypes vt ON v.VoteTypeId = vt.Id WHERE v.PostId = rp.PostId) AS VoteTypesForPost,
    (SELECT COUNT(*) FROM PostLinks pl2 WHERE pl2.PostId = rp.PostId) AS LinkCount
  FROM ranked_posts rp
  WHERE rp.rn = 1
),
windowed AS (
  SELECT
    cs.*,
    SUM(cs.Score) OVER (PARTITION BY cs.PostTypeId ORDER BY cs.Score DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningScore,
    AVG(cs.Reputation) OVER (PARTITION BY cs.PostTypeId) AS AvgAuthorReputation
  FROM cte_stats cs
),
aggregates AS (
  SELECT
    w.PostTypeId,
    COUNT(*) AS NumPosts,
    SUM(w.ViewCount) AS TotalViews,
    SUM(w.Score) AS TotalScore,
    MIN(w.CreationDate) AS EarliestPost,
    MAX(w.LastActivityDate) AS LatestActivity,
    AVG(w.RunningScore) AS AvgRunningScore
  FROM windowed w
  GROUP BY w.PostTypeId
),
tag_summary AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagPostCount,
    AVG(t.Score) AS AvgTagScore
  FROM Tags t
  JOIN Posts p ON p.Id = t.WikiPostId OR p.Id = t.ExcerptPostId
  GROUP BY t.TagName
)
SELECT
  w.PostId,
  w.Title,
  w.PostTypeId,
  CASE
    WHEN w.PostTypeId = 1 THEN 'Question'
    WHEN w.PostTypeId = 2 THEN 'Answer'
    ELSE 'Other'
  END AS PostTypeName,
  w.ViewCount,
  w.Score,
  w.RunningScore,
  w.AvgAuthorReputation,
  w.Reputation,
  w.OwnerDisplayName,
  w.Body,
  w.Tags,
  w.CommentCountForPost AS CommentCount,
  w.VoteTypesForPost,
  w.LinkCount AS LinkedPostCount,
  a.TotalViews AS AggSiteViews,
  a.TotalScore AS AggSiteScore,
  a.EarliestPost,
  a.LatestActivity
FROM windowed w
LEFT JOIN aggregates a ON a.PostTypeId = w.PostTypeId
LEFT JOIN tag_summary ts ON ts.TagName LIKE '%' -- placeholder to potentially extend tag insights
ORDER BY w.LastActivityDate DESC
LIMIT 100;