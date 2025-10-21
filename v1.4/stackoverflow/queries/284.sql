-- {"query": "284.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 13498} 
WITH TopQuestions AS (
  SELECT p.Id AS PostId,
         p.Title,
         p.Tags,
         p.ViewCount,
         p.Score,
         p.CreationDate,
         p.LastActivityDate,
         u.DisplayName AS OwnerName,
         u.Reputation AS OwnerReputation,
         ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS OwnerRank,
         p.OwnerUserId
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
)
SELECT
  tq.PostId,
  tq.Title,
  COALESCE(tq.OwnerName, 'Anonymous') AS OwnerName,
  COALESCE(tq.OwnerReputation, 0) AS OwnerReputation,
  tq.CreationDate,
  tq.LastActivityDate,
  tq.ViewCount,
  tq.Score,
  tq.OwnerRank,
  COALESCE((
     SELECT AVG(COALESCE(c.Score, 0))
     FROM Comments c
     WHERE c.PostId = tq.PostId
  ), 0) AS AvgCommentScore,
  COALESCE((
     SELECT COUNT(*) FROM Comments c WHERE c.PostId = tq.PostId
  ), 0) AS CommentCount,
  COALESCE(STRING_AGG(DISTINCT ta.Tag, ','), '') AS TagsList,
  COALESCE((
     SELECT SUM(v.BountyAmount)
     FROM Votes v
     WHERE v.PostId = tq.PostId
  ), 0) AS TotalBounty
FROM TopQuestions tq
LEFT JOIN LATERAL (
  SELECT unnest(string_to_array(substring(tq.Tags, 2, length(tq.Tags) - 2), '><')) AS Tag
) ta ON true
GROUP BY
  tq.PostId, tq.Title, tq.OwnerName, tq.OwnerReputation, tq.CreationDate,
  tq.LastActivityDate, tq.ViewCount, tq.Score, tq.OwnerRank
ORDER BY tq.Score DESC NULLS LAST
LIMIT 200;