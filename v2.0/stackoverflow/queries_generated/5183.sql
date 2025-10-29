-- {"query": "5183.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 678} 
WITH RankedPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.PostTypeId,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.LastActivityDate,
    p.Body,
    u.DisplayName AS AuthorName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    -- windowed metrics
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS UpvotesForThisPost,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS DownvotesForThisPost,
    SUM(CASE WHEN vt.Name = 'AcceptedByOriginator' THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS AcceptedVotes
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  WHERE p.PostTypeId IN (1,2)
),
Aggs AS (
  SELECT
    r.Id,
    r.Title,
    r.AuthorName,
    r.Reputation,
    r.UserCreationDate,
    r.CreationDate,
    r.LastActivityDate,
    r.ViewCount,
    r.Score,
    r.Tags,
    r.AnswerCount,
    r.CommentCount,
    r.FavoriteCount,
    r.Body,
    r.UpvotesForThisPost,
    r.DownvotesForThisPost,
    r.AcceptedVotes,
    -- derived dimensions
    CASE
      WHEN r.Score >= 10 THEN 'Trending'
      WHEN r.ViewCount > 1000 THEN 'Popular'
      ELSE 'New/Regular'
    END AS Category,
    CASE
      WHEN r.Reputation IS NULL THEN 0 ELSE r.Reputation
    END AS ReuptationSafe
  FROM RankedPosts r
),
Notebook AS (
  SELECT
    a.*,
    COUNT(*) OVER () AS TotalPosts
  FROM Aggs a
)
SELECT
  n.Id,
  n.Title,
  n.AuthorName,
  n.Category,
  n.TotalPosts,
  n.TotalPosts AS BenchmarkTotalPosts, -- redundant alias to stress set operations
  (n.UpvotesForThisPost - n.DownvotesForThisPost) AS NetScore,
  (EXTRACT(EPOCH FROM (n.LastActivityDate - n.CreationDate)) / 3600) AS HoursActive,
  ARRAY_AGG(DISTINCT t.TagName) FILTER (WHERE t.TagName IS NOT NULL) AS TagsList,
  n.Body AS PostBody,
  n.Views AS ViewsDeprecatedPlaceholder
FROM Notebook n
LEFT JOIN Tags t ON t.WikiPostId = n.Id
LEFT JOIN Posts p ON p.Id = n.Id
WHERE n.TotalPosts > 0
ORDER BY
  CASE WHEN n.Category = 'Trending' THEN 0 ELSE 1 END,
  n.LastActivityDate DESC
LIMIT 100;