-- {"query": "277.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 8119} 
WITH
RecentUserEngagement AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         COUNT(p.Id) FILTER (WHERE p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '30 days') AS PostsLast30,
         SUM(COALESCE(v.BountyAmount, 0)) AS TotalBounties,
         MAX(p.LastActivityDate) AS LastActive
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
RecentPostComments AS (
  SELECT p.Id AS PostId, COUNT(*) AS CommentCountLast7
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  WHERE c.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '7 days'
  GROUP BY p.Id
),
HotPosts AS (
  SELECT p.Id, p.Title, p.Score, p.ViewCount, p.OwnerUserId, p.LastEditorUserId,
         p.LastEditDate, p.CreationDate,
         ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS UserPostRank
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND (p.Score > 50 OR p.ViewCount > 2000)
),
PostLinksAgg AS (
  SELECT pl.PostId, COUNT(*) AS LinksCount
  FROM PostLinks pl
  GROUP BY pl.PostId
),
TagList AS (
  SELECT PostId, STRING_AGG(DISTINCT TagName, ', ') AS Tags
  FROM (
    SELECT t.ExcerptPostId AS PostId, t.TagName
    FROM Tags t
    WHERE t.ExcerptPostId IS NOT NULL
    UNION ALL
    SELECT t.WikiPostId AS PostId, t.TagName
    FROM Tags t
    WHERE t.WikiPostId IS NOT NULL
  ) x
  GROUP BY PostId
)
SELECT
  COALESCE(u.DisplayName, 'Community') AS UserDisplayName,
  u.Reputation,
  hp.Id AS PostId,
  hp.Title,
  hp.Score,
  hp.ViewCount,
  hp.CreationDate,
  ru.LastActive,
  rhc.CommentCountLast7,
  ru.PostsLast30,
  ru.TotalBounties,
  pla.LinksCount,
  tl.Tags,
  hp.UserPostRank,
  LOWER(hp.Title) AS TitleLower
FROM HotPosts hp
LEFT JOIN Users u ON u.Id = hp.OwnerUserId
LEFT JOIN RecentUserEngagement ru ON ru.UserId = u.Id
LEFT JOIN RecentPostComments rhc ON rhc.PostId = hp.Id
LEFT JOIN PostLinksAgg pla ON pla.PostId = hp.Id
LEFT JOIN TagList tl ON tl.PostId = hp.Id
ORDER BY hp.UserPostRank, hp.Score DESC
LIMIT 100;