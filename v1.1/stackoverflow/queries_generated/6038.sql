-- {"query": "6038.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 701} 
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.Views,
    p.OwnerUserId,
    u.DisplayName AS OwnerName,
    pc.Count AS CommentCount
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS Count
    FROM Comments
    GROUP BY PostId
  ) pc ON p.Id = pc.PostId
  WHERE p.PostTypeId = 1 AND p.CreationDate >= NOW() - INTERVAL '30 days'
),
tag_burst AS (
  SELECT
    t.TagName,
    t.Count,
    t2.PostId
  FROM Tags t
  JOIN LATERAL (
    SELECT t2.PostId
    FROM Posts t2
    WHERE t2.Tags LIKE '%' || t.TagName || '%'
    LIMIT 1
  ) AS t2 ON true
  WHERE t.IsModeratorOnly = 0
),
activity AS (
  SELECT
    r.PostId,
    r.Title,
    r.OwnerName,
    r.CreationDate,
    r.CommentCount,
    r.Score,
    r.Views
  FROM recent_questions r
  LEFT JOIN PostHistory ph
    ON ph.PostId = r.PostId
  LEFT JOIN PostLinks pl
    ON pl.PostId = r.PostId
  WHERE ph.Id IS NULL OR ph.CreationDate = (
    SELECT MAX(CreationDate) FROM PostHistory WHERE PostId = r.PostId
  )
),
complex AS (
  SELECT
    a.PostId,
    a.Title,
    a.OwnerName,
    a.CreationDate,
    a.CommentCount,
    a.Score,
    a.Views,
    ROW_NUMBER() OVER (PARTITION BY a.OwnerName ORDER BY a.Views DESC, a.Score DESC) AS rn,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY a.PostId) AS UpVotesForPost,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY a.PostId) AS DownVotesForPost
  FROM activity a
  LEFT JOIN Votes v ON v.PostId = a.PostId
  LEFT JOIN PostLinks pl ON pl.PostId = a.PostId
)
SELECT
  c.PostId,
  c.Title,
  c.OwnerName,
  c.CreationDate,
  c.CommentCount,
  c.Score,
  c.Views,
  c.UpVotesForPost,
  c.DownVotesForPost,
  CASE
    WHEN c.Score > 50 THEN 'Hot'
    WHEN c.Views > 10000 THEN 'Popular'
    ELSE 'New/Medium'
  END AS TrendBucket,
  STRING_AGG(DISTINCT t.TagName, ',') OVER (PARTITION BY c.PostId) AS TagsOnPost,
  COUNT(*) OVER () AS TotalPostsInBenchmark
FROM complex c
LEFT JOIN Tags t ON t.ExcerptPostId = c.PostId OR t.WikiPostId = c.PostId
QUALIFY rn = 1
ORDER BY c.Views DESC NULLS LAST, c.Score DESC NULLS LAST
LIMIT 100;