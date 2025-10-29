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
  n.TotalPosts AS BenchmarkTotalPosts,
  (n.UpvotesForThisPost - n.DownvotesForThisPost) AS NetScore,
  (CAST(EXTRACT(EPOCH FROM (n.LastActivityDate - n.CreationDate)) AS double precision) / 3600) AS HoursActive,
  ARRAY_AGG(DISTINCT t.TagName) FILTER (WHERE t.TagName IS NOT NULL) AS TagsList,
  n.Body AS PostBody,
  n.ViewCount AS ViewsDeprecatedPlaceholder
FROM Notebook n
LEFT JOIN Tags t ON t.WikiPostId = n.Id
LEFT JOIN Posts p ON p.Id = n.Id
WHERE n.TotalPosts > 0
GROUP BY
  n.Id,
  n.Title,
  n.AuthorName,
  n.Category,
  n.TotalPosts,
  n.UpvotesForThisPost,
  n.DownvotesForThisPost,
  n.LastActivityDate,
  n.CreationDate,
  n.Body,
  n.ViewCount
ORDER BY
  CASE WHEN n.Category = 'Trending' THEN 0 ELSE 1 END,
  n.LastActivityDate DESC
LIMIT 100;