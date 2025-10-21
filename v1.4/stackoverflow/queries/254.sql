-- {"query": "254.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 6869} 
WITH
tag_extracted AS (
  SELECT p.Id AS PostId, p.Title, p.Score, p.ViewCount, p.CreationDate, p.OwnerUserId, p.OwnerDisplayName,
         substring(p.Tags, 2, length(p.Tags) - 2) AS rawTags
  FROM Posts p
  WHERE p.PostTypeId = 1
),
tag_split AS (
  SELECT te.PostId, te.Title, te.Score, te.ViewCount, te.CreationDate, te.OwnerUserId, te.OwnerDisplayName,
         unnest(string_to_array(te.rawTags, '><')) AS TagName
  FROM tag_extracted te
  WHERE te.rawTags IS NOT NULL
),
top_tags AS (
  SELECT TagName, COUNT(*) AS PostCount, AVG(Score) AS AvgScore
  FROM tag_split
  GROUP BY TagName
  ORDER BY AvgScore DESC NULLS LAST, PostCount DESC
  LIMIT 20
),
per_post AS (
  SELECT tt.TagName, ts.PostId, ts.Title, ts.Score, ts.ViewCount, ts.CreationDate, ts.OwnerUserId, ts.OwnerDisplayName,
         COALESCE(u.Reputation, 0) AS OwnerReputation,
         COALESCE(nv.NetVotes, 0) AS NetVotes,
         COALESCE(cc.CommentCount, 0) AS CommentCount,
         badge.BadgeName, badge.BadgeClass
  FROM top_tags tt
  JOIN tag_split ts ON ts.TagName = tt.TagName
  LEFT JOIN LATERAL (
     SELECT SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 END) AS NetVotes
     FROM Votes v WHERE v.PostId = ts.PostId
  ) nv ON true
  LEFT JOIN LATERAL (
     SELECT COUNT(*) AS CommentCount FROM Comments c WHERE c.PostId = ts.PostId
  ) cc ON true
  LEFT JOIN Users u ON u.Id = ts.OwnerUserId
  LEFT JOIN LATERAL (
     SELECT b.Name AS BadgeName, b.Class AS BadgeClass
     FROM Badges b
     WHERE b.UserId = ts.OwnerUserId
     ORDER BY b.Date DESC
     LIMIT 1
  ) badge ON true
),
ranked AS (
  SELECT TagName, PostId, Title, Score, ViewCount, CreationDate, OwnerUserId, OwnerDisplayName, OwnerReputation,
         NetVotes, CommentCount, BadgeName, BadgeClass,
         ROW_NUMBER() OVER (PARTITION BY TagName ORDER BY (Score + NetVotes * 2.0) DESC, ViewCount DESC, CreationDate DESC) AS rn
  FROM per_post
)
SELECT *
FROM ranked
WHERE rn <= 3
ORDER BY TagName, rn;