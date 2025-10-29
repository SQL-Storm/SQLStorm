-- {"query": "5438.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1242}
WITH
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    COALESCE(p.PostCount, 0) AS PostCount,
    COALESCE(cmt.CommentCount, 0) AS CommentCount,
    COALESCE(bdg.BadgeCount, 0) AS BadgeCount,
    ROW_NUMBER() OVER (
      ORDER BY u.Reputation DESC,
               (COALESCE(p.PostCount,0) + COALESCE(cmt.CommentCount,0) * 0.5 + COALESCE(bdg.BadgeCount,0) * 0.2) DESC,
               u.LastAccessDate DESC
    ) AS rn
  FROM Users u
  LEFT JOIN (
    SELECT OwnerUserId, COUNT(*) AS PostCount
    FROM Posts
    WHERE PostTypeId IN (1,2,3,4,5)
    GROUP BY OwnerUserId
  ) p ON p.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY UserId
  ) cmt ON cmt.UserId = u.Id
  LEFT JOIN (
    SELECT UserId, COUNT(*) AS BadgeCount
    FROM Badges
    GROUP BY UserId
  ) bdg ON bdg.UserId = u.Id
),
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Title,
    p.Tags,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.FavoriteCount,
    CASE
      WHEN p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30' DAY) THEN 1
      ELSE 0
    END AS IsNew30,
    CASE
      WHEN p.LastActivityDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '7' DAY) THEN 1
      ELSE 0
    END AS IsActive7
  FROM Posts p
  WHERE p.PostTypeId IN (1,2)
),
LinkedPairs AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkTypeName
  FROM PostLinks pl
  JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE lt.Name IN ('Linked','Duplicate')
),
TagDynamics AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    COALESCE(qs.RecentQuestionCount,0) AS RecentQuestionCount,
    (t.Count * 1.0) + (COALESCE(qs.RecentQuestionCount,0) * 0.5) AS TagScore
  FROM Tags t
  LEFT JOIN (
    SELECT tagname, COUNT(*) AS RecentQuestionCount
    FROM Posts p,
         LATERAL unnest(string_to_array(p.Tags, '><')) AS tagname
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '14' DAY)
    GROUP BY tagname
  ) qs ON qs.tagname = t.TagName
  WHERE t.TagName IS NOT NULL
),
AggFrame AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.LastAccessDate,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS FrameRank,
    COUNT(p.Id) AS PostsInBenchmark,
    SUM(p.ViewCount) AS TotalViews,
    AVG(p.Score) AS AvgPostScore
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.LastAccessDate
)
SELECT
  ui.rn AS ranking_within_benchmark,
  ui.UserId,
  ui.DisplayName,
  ui.Reputation,
  ui.CreationDate AS UserCreationDate,
  ui.LastAccessDate,
  ui.Location,
  ui.PostCount,
  ui.CommentCount,
  ui.BadgeCount,
  ra.PostId AS BenchmarkPostId,
  ra.Title AS BenchmarkPostTitle,
  ra.Tags AS BenchmarkPostTags,
  ra.PostTypeId AS BenchmarkPostType,
  ra.Score AS BenchmarkPostScore,
  ra.ViewCount AS BenchmarkPostViews,
  ga.FrameRank AS FrameRank,
  ga.PostsInBenchmark,
  ga.TotalViews,
  ga.AvgPostScore,
  (
    SELECT ARRAY_AGG(DISTINCT tg.TagName)
    FROM Posts p2
    , LATERAL unnest(string_to_array(p2.Tags, '><')) AS tg(TagName)
    WHERE p2.Id = ra.PostId
      AND p2.OwnerUserId = ui.UserId
  ) AS AssociatedTagSet
FROM UserActivity ui
LEFT JOIN RecentActivity ra ON ra.OwnerUserId = ui.UserId
LEFT JOIN AggFrame ga ON ga.UserId = ui.UserId
WHERE ui.rn <= 100
GROUP BY
  ui.rn,
  ui.UserId,
  ui.DisplayName,
  ui.Reputation,
  ui.CreationDate,
  ui.LastAccessDate,
  ui.Location,
  ui.PostCount,
  ui.CommentCount,
  ui.BadgeCount,
  ra.PostId,
  ra.Title,
  ra.Tags,
  ra.PostTypeId,
  ra.Score,
  ra.ViewCount,
  ga.FrameRank,
  ga.PostsInBenchmark,
  ga.TotalViews,
  ga.AvgPostScore
ORDER BY ui.Reputation DESC, ui.LastAccessDate DESC;