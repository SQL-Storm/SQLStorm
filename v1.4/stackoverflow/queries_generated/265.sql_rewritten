-- {"query": "265.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 8494} 
WITH 
Last7 AS (
  SELECT p.Id AS PostId, p.OwnerUserId, p.Title, p.Score, p.ViewCount, p.CreationDate, p.Tags,
         ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS Rank7
  FROM Posts p
  WHERE p.PostTypeId = 1 AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '7 days'
),
Last30 AS (
  SELECT p.Id AS PostId, p.OwnerUserId, p.Title, p.Score, p.ViewCount, p.CreationDate, p.Tags,
         ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC, p.Score DESC) AS Rank30
  FROM Posts p
  WHERE p.PostTypeId = 1 AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
),
TopPosts AS (
  SELECT PostId, OwnerUserId, Title, Score, ViewCount, CreationDate, Tags, Rank7 AS Rank, '7d' AS RangeTag
  FROM Last7
  WHERE Rank7 <= 50
  UNION ALL
  SELECT PostId, OwnerUserId, Title, Score, ViewCount, CreationDate, Tags, Rank30, '30d'
  FROM Last30
  WHERE Rank30 <= 50
),
TagList AS (
  SELECT p.Id AS PostId,
         STRING_AGG(t, ',') AS TagList
  FROM Posts p
  CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) AS t
  WHERE p.PostTypeId = 1
  GROUP BY p.Id
),
CommentStats AS (
  SELECT p.Id AS PostId, COUNT(c.Id) AS CommentCount
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  WHERE p.PostTypeId = 1
  GROUP BY p.Id
),
UpVotes AS (
  SELECT p.Id AS PostId, COUNT(v.Id) AS UpVoteCount
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 2
  WHERE p.PostTypeId = 1
  GROUP BY p.Id
),
Voters AS (
  SELECT p.Id AS PostId,
         STRING_AGG(DISTINCT u.DisplayName, ',') AS VoterNames
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 2
  LEFT JOIN Users u ON v.UserId = u.Id
  WHERE p.PostTypeId = 1
  GROUP BY p.Id
),
BadgeCount AS (
  SELECT b.UserId, COUNT(*) AS BadgeCount
  FROM Badges b
  GROUP BY b.UserId
)
SELECT
  tp.PostId,
  tp.OwnerUserId,
  u.DisplayName AS OwnerName,
  tp.Title,
  tp.Score,
  tp.ViewCount,
  tp.CreationDate,
  COALESCE(tl.TagList, '') AS TagList,
  COALESCE(cs.CommentCount, 0) AS CommentCount,
  COALESCE(uv.UpVoteCount, 0) AS UpVotes,
  COALESCE(v.VoterNames, '') AS VoterNames,
  COALESCE(bc.BadgeCount, 0) AS BadgeCount,
  ROW_NUMBER() OVER (PARTITION BY tp.OwnerUserId ORDER BY tp.Score DESC, tp.ViewCount DESC) AS PerOwnerRank
FROM TopPosts tp
JOIN Users u ON u.Id = tp.OwnerUserId
LEFT JOIN TagList tl ON tl.PostId = tp.PostId
LEFT JOIN CommentStats cs ON cs.PostId = tp.PostId
LEFT JOIN UpVotes uv ON uv.PostId = tp.PostId
LEFT JOIN Voters v ON v.PostId = tp.PostId
LEFT JOIN BadgeCount bc ON bc.UserId = tp.OwnerUserId
WHERE (tp.Score > 0 OR tp.ViewCount > 0)
ORDER BY PerOwnerRank ASC, tp.CreationDate DESC
LIMIT 500;