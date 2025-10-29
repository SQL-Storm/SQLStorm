-- {"query": "5384.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1017} 
WITH recent_user_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId
  FROM Users u
),
tag_wiki_activity AS (
  SELECT
    t.TagName,
    p.Id AS PostId,
    p.Title,
    p.CreationDate AS PostCreationDate,
    p.Score AS PostScore,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    -- correlated subquery: count of comments on the post
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    -- window function: cumulative distinct tags count over post creation date per owner
    COUNT(DISTINCT t.TagName) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS OwnerTagCount
  FROM Posts p
  JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%' -- simplistic tag linkage for demo
  WHERE p.PostTypeId = 1 -- questions
    AND p.CreationDate >= NOW() - INTERVAL '180 days'
),
mixed_view AS (
  SELECT
    rua.UserId,
    rua.DisplayName,
    rua.Reputation,
    rua.CreationDate,
    rua.LastAccessDate,
    rua.Location,
    rua.Views,
    rua.UpVotes,
    rua.DownVotes,
    rua.ProfileImageUrl,
    rua.EmailHash,
    rua.AccountId,
    COUNT(DISTINCT tt.TagName) AS DistinctTagCount,
    SUM(p.Score) AS TotalQuestionScore,
    SUM(p.ViewCount) AS TotalViewCount
  FROM recent_user_activity rua
  LEFT JOIN Posts p ON p.OwnerUserId = rua.Id AND p.PostTypeId = 1
  LEFT JOIN Tags tt ON p.Tags LIKE '%' || tt.TagName || '%'
  WHERE rua.Id IN (SELECT Id FROM Users WHERE Reputation > 100)
  GROUP BY rua.UserId, rua.DisplayName, rua.Reputation, rua.CreationDate, rua.LastAccessDate, rua.Location,
           rua.Views, rua.UpVotes, rua.DownVotes, rua.ProfileImageUrl, rua.EmailHash, rua.AccountId
),
complex_stats AS (
  SELECT
    mv.UserId,
    mv.DisplayName,
    mv.Reputation,
    mv.TotalQuestionScore,
    mv.TotalViewCount,
    mv.DistinctTagCount,
    -- compute a synthetic performance index with NULL-safe expressions
    (COALESCE(mv.TotalQuestionScore, 0) * 1.5
     + COALESCE(mv.TotalViewCount, 0) * 0.75
     + COALESCE(mv.DistinctTagCount, 0) * 2.0) AS PerformanceIndex,
    -- correlation-friendly metrics via window
    SUM(COALESCE(p.Score, 0)) OVER (PARTITION BY mv.UserId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningScore
  FROM mixed_view mv
  LEFT JOIN Posts p ON p.OwnerUserId = mv.UserId AND p.PostTypeId = 1
  GROUP BY mv.UserId, mv.DisplayName, mv.Reputation, mv.TotalQuestionScore, mv.TotalViewCount, mv.DistinctTagCount
)
SELECT
  cs.UserId,
  cs.DisplayName,
  cs.Reputation,
  cs.TotalQuestionScore,
  cs.TotalViewCount,
  cs.DistinctTagCount,
  cs.PerformanceIndex,
  cs.RunningScore,
  -- cross join with top-voted post details to stress join/predicate logic
  (SELECT TOP 1 q.Id FROM Posts q WHERE q.OwnerUserId = cs.UserId AND q.PostTypeId = 1 ORDER BY q.Score DESC, q.CreationDate DESC) AS TopQuestionId,
  (SELECT TOP 1 q.Title FROM Posts q WHERE q.OwnerUserId = cs.UserId AND q.PostTypeId = 1 ORDER BY q.Score DESC, q.CreationDate DESC) AS TopQuestionTitle,
  -- optional advanced predicate: posts with at least two different tags in the Tags field
  (SELECT COUNT(DISTINCT t.TagName)
     FROM Posts p2
     JOIN Tags t ON p2.Tags LIKE '%' || t.TagName || '%'
     WHERE p2.OwnerUserId = cs.UserId
       AND p2.PostTypeId = 1) AS TagVariety
FROM complex_stats cs
ORDER BY cs.PerformanceIndex DESC, cs.RunningScore DESC, cs.Reputation DESC
LIMIT 100;