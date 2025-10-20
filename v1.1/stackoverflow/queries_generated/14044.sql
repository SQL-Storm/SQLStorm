-- {"query": "14044.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 105075, "output_tokens": 44370} 
WITH cte1 AS (
  SELECT 
    p.Id AS PostId, 
    p.PostTypeId, 
    p.OwnerUserId, 
    p.CreationDate, 
    p.LastActivityDate, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    p.CommentCount, 
    p.FavoriteCount, 
    CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS Closed,
    CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS CommunityOwned,
    STRING_AGG(DISTINCT t.TagName, '><') AS Tags
  FROM Posts p
  LEFT JOIN Tags t ON p.Tags LIKE '%><' + t.TagName + '><%'
  GROUP BY 
    p.Id, 
    p.PostTypeId, 
    p.OwnerUserId, 
    p.CreationDate, 
    p.LastActivityDate, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    p.CommentCount, 
    p.FavoriteCount, 
    p.ClosedDate, 
    p.CommunityOwnedDate
),
cte2 AS (
  SELECT 
    p.Id AS PostId,
    p.ParentId,
    p.AcceptedAnswerId,
    DENSE_RANK() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate) AS AnswerRank
  FROM Posts p
  WHERE p.PostTypeId = 2
),
cte3 AS (
  SELECT 
    c.PostId,
    c.Score,
    c.CreationDate,
    u.Reputation,
    u.DisplayName
  FROM Comments c
  JOIN Users u ON c.UserId = u.Id
),
cte4 AS (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.CreationDate,
    p.Title,
    p.Body,
    p.Tags,
    CASE WHEN p.ClosedDate IS NOT NULL THEN cr.Name ELSE NULL END AS ClosedReason
  FROM Posts p
  LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
  LEFT JOIN CloseReasonTypes cr ON CAST(ph.Comment AS int) = cr.Id
  WHERE p.PostTypeId = 1
)
SELECT 
  c1.PostId,
  c1.PostTypeId,
  c1.OwnerUserId,
  c1.CreationDate,
  c1.LastActivityDate,
  c1.Score,
  c1.ViewCount,
  c1.AnswerCount,
  c1.CommentCount,
  c1.FavoriteCount,
  c1.Closed,
  c1.CommunityOwned,
  c1.Tags,
  c2.ParentId,
  c2.AcceptedAnswerId,
  c2.AnswerRank,
  c3.Score AS CommentScore,
  c3.CreationDate AS CommentCreationDate,
  c3.Reputation AS CommentUserReputation,
  c3.DisplayName AS CommentUserName,
  c4.Title,
  c4.Body,
  c4.ClosedReason
FROM cte1 c1
LEFT JOIN cte2 c2 ON c1.PostId = c2.PostId
LEFT JOIN cte3 c3 ON c1.PostId = c3.PostId
LEFT JOIN cte4 c4 ON c1.PostId = c4.PostId
ORDER BY c1.PostId, c2.AnswerRank, c3.CreationDate;