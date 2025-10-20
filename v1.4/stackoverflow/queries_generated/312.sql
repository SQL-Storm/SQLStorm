-- {"query": "312.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 19065} 
WITH
Core AS (
  SELECT p.Id, p.Title, p.PostTypeId, p.CreationDate, p.LastActivityDate,
         p.OwnerUserId, p.ViewCount, p.Score
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2) -- Question(1) and Answer(2)
),
TagPieces AS (
  SELECT c.Id AS PostId, TRIM(t.TagName) AS TagName
  FROM Core c
  JOIN Posts p ON p.Id = c.Id
  CROSS JOIN LATERAL UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS t(TagName)
  WHERE p.Tags IS NOT NULL
),
TagAgg AS (
  SELECT PostId, STRING_AGG(TagName, ', ') AS TagList
  FROM TagPieces
  GROUP BY PostId
),
CommentCounts AS (
  SELECT PostId, COUNT(*) AS CommentCount
  FROM Comments
  GROUP BY PostId
),
BountySums AS (
  SELECT PostId, COALESCE(SUM(BountyAmount), 0) AS BountySum
  FROM Votes
  WHERE VoteTypeId = 8
  GROUP BY PostId
),
Weighted AS (
  SELECT c.Id, c.Title, c.PostTypeId, c.CreationDate, c.LastActivityDate,
         c.OwnerUserId, c.ViewCount, c.Score,
         COALESCE(cc.CommentCount, 0) AS CommentCount,
         COALESCE(bs.BountySum, 0) AS BountySum,
         ta.TagList,
         ROW_NUMBER() OVER (PARTITION BY c.PostTypeId ORDER BY c.LastActivityDate DESC) AS PostRank,
         CASE WHEN COALESCE(cc.CommentCount, 0) > 20 OR c.ViewCount > 1000 THEN TRUE ELSE FALSE END AS IsPopular
  FROM Core c
  LEFT JOIN TagAgg ta ON ta.PostId = c.Id
  LEFT JOIN CommentCounts cc ON cc.PostId = c.Id
  LEFT JOIN BountySums bs ON bs.PostId = c.Id
),
SetA AS (
  SELECT w.Id, w.Title, w.PostTypeId, w.CreationDate, w.LastActivityDate,
         w.OwnerUserId, w.ViewCount, w.Score, w.CommentCount, w.BountySum,
         w.TagList, w.PostRank, w.IsPopular
  FROM Weighted w
  WHERE w.PostTypeId = 1
  ORDER BY w.LastActivityDate DESC
  LIMIT 200
),
SetB AS (
  SELECT w.Id, w.Title, w.PostTypeId, w.CreationDate, w.LastActivityDate,
         w.OwnerUserId, w.ViewCount, w.Score, w.CommentCount, w.BountySum,
         w.TagList, w.PostRank, w.IsPopular
  FROM Weighted w
  WHERE w.PostTypeId = 2
  ORDER BY w.LastActivityDate DESC
  LIMIT 200
)
SELECT s.Id, s.Title, s.PostTypeId, s.CreationDate, s.LastActivityDate,
       s.OwnerUserId, u.DisplayName AS OwnerDisplayName, u.Reputation AS OwnerReputation,
       s.ViewCount, s.Score, s.CommentCount, s.BountySum,
       s.TagList, s.PostRank, s.IsPopular
FROM (
  SELECT * FROM SetA
  UNION ALL
  SELECT * FROM SetB
) s
LEFT JOIN Users u ON s.OwnerUserId = u.Id
ORDER BY s.LastActivityDate DESC
LIMIT 400;