-- {"query": "48097.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 575} 
SELECT
  p.Id,
  p.Title,
  p.CreationDate AS PostCreationDate,
  pt.Name AS PostTypeName,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation AS OwnerReputation,
  (
    SELECT
      COUNT(c.Id)
    FROM Comments AS c
    WHERE
      c.PostId = p.Id
  ) AS CommentCount,
  (
    SELECT
      SUM(v.VoteTypeId) -- Arbitrary aggregation for performance test
    FROM Votes AS v
    WHERE
      v.PostId = p.Id
  ) AS VoteSum,
  (
    SELECT
      COUNT(ph.Id)
    FROM PostHistory AS ph
    WHERE
      ph.PostId = p.Id AND ph.PostHistoryTypeId IN (2, 5) -- Edits to body
  ) AS BodyEditCount,
  p.Score,
  p.ViewCount,
  p.AnswerCount,
  p.FavoriteCount,
  p.ClosedDate,
  p.CommunityOwnedDate,
  (
    SELECT
      COUNT(pl.Id)
    FROM PostLinks AS pl
    WHERE
      pl.PostId = p.Id AND pl.LinkTypeId = 3 -- Duplicates
  ) AS DuplicateLinkCount,
  (
    SELECT
      COUNT(DISTINCT ph.UserId)
    FROM PostHistory AS ph
    WHERE
      ph.PostId = p.Id AND ph.PostHistoryTypeId IN (1, 4, 7) -- Title related history
  ) AS DistinctTitleEditorCount,
  (
    SELECT
      AVG(c.Score)
    FROM Comments AS c
    WHERE
      c.PostId = p.Id
  ) AS AverageCommentScore,
  (
    SELECT
      MAX(v.CreationDate)
    FROM Votes AS v
    WHERE
      v.PostId = p.Id
  ) AS LastVoteDate
FROM Posts AS p
JOIN PostTypes AS pt
  ON p.PostTypeId = pt.Id
LEFT JOIN Users AS u
  ON p.OwnerUserId = u.Id
WHERE
  p.CreationDate >= '2023-01-01' AND p.CreationDate < '2024-01-01'
  AND pt.Id = 1 -- Questions only
  AND p.Score > 10
  AND p.ViewCount > 1000
ORDER BY
  p.LastActivityDate DESC
LIMIT 1000;