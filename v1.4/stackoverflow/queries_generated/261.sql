-- {"query": "261.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 8836} 
WITH
ActiveUsers AS (
  SELECT Id, DisplayName, Reputation, Views
  FROM Users
  WHERE Reputation > 1000
),
PostCommentCounts AS (
  SELECT PostId, COUNT(*) AS CommentCount
  FROM Comments
  GROUP BY PostId
),
PostVotes AS (
  SELECT PostId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
                 SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
  FROM Votes
  GROUP BY PostId
)
SELECT
  p.Id AS PostId,
  pt.Name AS PostType,
  p.Title,
  COALESCE(p.OwnerDisplayName, u.DisplayName, 'Unknown') AS Owner,
  COALESCE(u.Reputation, 0) AS OwnerReputation,
  p.CreationDate,
  p.LastActivityDate,
  p.Score,
  p.ViewCount,
  COALESCE(pcc.CommentCount, 0) AS CommentCount,
  COALESCE(pv.Upvotes, 0) AS Upvotes,
  COALESCE(pv.Downvotes, 0) AS Downvotes,
  (SELECT COALESCE(string_agg(t, ','), '')
     FROM unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS t) AS TagList,
  a.DisplayName AS TopAuthor,
  ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS TypeRank,
  CASE WHEN (SELECT COUNT(*) FROM Votes v2 WHERE v2.PostId = p.Id AND v2.VoteTypeId = 2) >
            (SELECT COUNT(*) FROM Votes v3 WHERE v3.PostId = p.Id AND v3.VoteTypeId = 3)
       THEN true ELSE false END AS IsPopular
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN ActiveUsers a ON a.Id = p.OwnerUserId
LEFT JOIN PostCommentCounts pcc ON p.Id = pcc.PostId
LEFT JOIN PostVotes pv ON p.Id = pv.PostId
WHERE p.CreationDate >= now() - interval '180 days'
  AND p.PostTypeId IN (1, 2)
ORDER BY p.CreationDate DESC
LIMIT 500;