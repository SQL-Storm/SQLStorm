-- {"query": "5442.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1004} 
WITH
recent_user_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.WebsiteUrl,
    u.AboutMe,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.LastAccessDate DESC) AS rn
  FROM Users u
),
top_post_contrib AS (
  SELECT
    p.OwnerUserId,
    p.Id AS PostId,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.LastActivityDate,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    p.AnswerCount,
    COALESCE(vt.Name, 'Unknown') AS VoteTypeName,
    v.Count AS VoteCount,
    v.CreationDate AS VoteDate
  FROM Posts p
  LEFT JOIN Votes v
    ON v.PostId = p.Id
  LEFT JOIN VoteTypes vt
    ON vt.Id = v.VoteTypeId
  WHERE p.PostTypeId IN (1,2) -- Questions and Answers
    AND p.CreationDate > NOW() - INTERVAL '180 days'
),
tag_popularity AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    p.Id AS PostId,
    p.Title AS PostTitle,
    p.OwnerUserId,
    p.CreationDate AS PostDate
  FROM Tags t
  LEFT JOIN Posts p ON t.WikiPostId = p.Id OR t.ExcerptPostId = p.Id
  WHERE t.IsModeratorOnly = 0
),
correlated_subquery AS (
  SELECT
    a.PostId,
    a.Title,
    a.Score,
    a.ViewCount,
    a.Tags,
    a.PostTypeId,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.Id) AS CommentTotal,
    (SELECT AVG(v2.Count) FROM Votes v2 WHERE v2.PostId = a.Id) AS AvgVoteCount
  FROM Posts a
  WHERE a.LastActivityDate > NOW() - INTERVAL '90 days'
)
SELECT
  -- Overall benchmarking metrics
  (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1) AS TotalQuestions,
  (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) AS AvgQuestionScore,
  (SELECT MAX(ViewCount) FROM Posts) AS MaxPostViews,
  (SELECT COUNT(*) FROM Votes v WHERE v.VoteTypeId = 2) AS TotalUpvotes,
  (SELECT COUNT(*) FROM Votes v WHERE v.VoteTypeId = 3) AS TotalDownvotes,
  (SELECT AVG(Length(Body)) FROM Posts) AS AvgBodyLength,
  -- Outermost join pattern demonstration with correlations
  u.DisplayName AS BenchmarkUser,
  p.Title AS BenchmarkPostTitle,
  p.Score AS BenchmarkPostScore,
  p.ViewCount AS BenchmarkPostViews,
  p.Tags AS BenchmarkPostTags,
  p.CreationDate AS BenchmarkPostDate,
  -- Window function usage over recent user activity
  (SELECT ARRAY_AGG(DisplayName ORDER BY LastAccessDate DESC) FROM recent_user_activity WHERE rn = 1) AS LastActiveUsers,
  -- Complex predicate / NULL handling and expressions
  CASE
    WHEN p.OwnerUserId IS NULL THEN 'Anonymous'
    WHEN p.OwnerUserId = -1 THEN 'Community'
    ELSE u.DisplayName
  END AS PostOwnerDisplayName,
  CASE
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    ELSE 'Open'
  END AS PostStatus
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 2
LEFT JOIN TagNames tn ON tn.PostId = p.Id
LEFT JOIN correlated_subquery cs ON cs.PostId = p.Id
LEFT JOIN recent_user_activity ru ON ru.UserId = p.OwnerUserId
WHERE
  p.LastActivityDate > NOW() - INTERVAL '60 days'
  AND (p.Score > 0 OR p.ViewCount > 100)
  AND (p.Tags LIKE '%<stack-overflow>%'
       OR p.Body LIKE '%benchmark%')
GROUP BY
  u.DisplayName,
  p.Title,
  p.Score,
  p.ViewCount,
  p.Tags,
  p.CreationDate,
  p.OwnerUserId,
  p.ClosedDate,
  p.LastActivityDate
ORDER BY
  p.LastActivityDate DESC
LIMIT 100;