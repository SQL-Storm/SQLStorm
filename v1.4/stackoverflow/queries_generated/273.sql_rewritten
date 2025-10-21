-- {"query": "273.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 9050} 
WITH
RecentPosts AS (
  SELECT p.Id, p.PostTypeId, p.Title, p.OwnerUserId, p.Tags, p.Score, p.ViewCount, p.CreationDate, p.LastActivityDate
  FROM Posts p
  WHERE p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '365 days'
    AND p.PostTypeId IN (1, 2)
),
CommentCounts AS (
  SELECT rp.Id AS PostId, COUNT(c.Id) AS CommentCount
  FROM RecentPosts rp
  LEFT JOIN Comments c ON c.PostId = rp.Id
  GROUP BY rp.Id
),
TagAgg AS (
  SELECT rp.Id AS PostId,
         STRING_AGG(DISTINCT t.TagName, ',') AS TagList
  FROM RecentPosts rp
  CROSS JOIN LATERAL unnest(string_to_array(substring(rp.Tags, 2, length(rp.Tags)-2), '><')) AS t(TagName)
  GROUP BY rp.Id
),
Commentable AS (
  SELECT rp.Id, rp.Title, rp.PostTypeId, rp.OwnerUserId, rp.Score, rp.ViewCount,
         COALESCE(cc.CommentCount, 0) AS CommentCount
  FROM RecentPosts rp
  LEFT JOIN CommentCounts cc ON cc.PostId = rp.Id
),
Ranked AS (
  SELECT c.Id, c.Title, c.PostTypeId, c.OwnerUserId, c.Score, c.ViewCount, c.CommentCount,
         (c.Score * 3.0 + c.ViewCount * 0.4 + c.CommentCount * 1.2) AS Relevance
  FROM Commentable c
),
RankedWindow AS (
  SELECT r.Id, r.Title, r.PostTypeId, r.OwnerUserId, r.Score, r.ViewCount, r.CommentCount, r.Relevance,
         ROW_NUMBER() OVER (PARTITION BY r.PostTypeId ORDER BY r.Relevance DESC) AS RankInType
  FROM Ranked r
)
SELECT rw.Id AS PostId,
       rw.Title,
       rw.PostTypeId,
       rw.OwnerUserId,
       u.DisplayName AS OwnerDisplayName,
       u.Reputation,
       rw.Score,
       rw.ViewCount,
       rw.CommentCount,
       ta.TagList,
       rw.RankInType,
       rw.Relevance
FROM RankedWindow rw
LEFT JOIN Users u ON u.Id = rw.OwnerUserId
LEFT JOIN TagAgg ta ON ta.PostId = rw.Id
WHERE rw.RankInType <= 100

UNION ALL

SELECT rw2.Id AS PostId,
       rw2.Title,
       rw2.PostTypeId,
       rw2.OwnerUserId,
       u2.DisplayName AS OwnerDisplayName,
       u2.Reputation,
       rw2.Score,
       rw2.ViewCount,
       rw2.CommentCount,
       ta2.TagList,
       rw2.RankInType,
       rw2.Relevance
FROM RankedWindow rw2
LEFT JOIN Users u2 ON u2.Id = rw2.OwnerUserId
LEFT JOIN TagAgg ta2 ON ta2.PostId = rw2.Id
WHERE rw2.CommentCount > 20
ORDER BY Relevance DESC
LIMIT 250;