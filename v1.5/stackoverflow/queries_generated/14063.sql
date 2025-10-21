-- {"query": "14063.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 149440, "output_tokens": 64253} 

WITH cte1 AS (
  SELECT 
    p.Id, 
    p.PostTypeId, 
    p.OwnerUserId, 
    p.CreationDate, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    p.CommentCount, 
    p.FavoriteCount, 
    p.ClosedDate, 
    p.CommunityOwnedDate, 
    CASE 
      WHEN p.ClosedDate IS NOT NULL THEN (SELECT Name FROM CloseReasonTypes WHERE Id = CAST(ph.Comment AS int)) 
      ELSE NULL 
    END AS CloseReason,
    CASE
      WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
      WHEN ph.PostHistoryTypeId = 16 THEN 'Community Owned'
      ELSE NULL
    END AS CommunityOwned
  FROM Posts p
  LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (10, 16)
  WHERE p.PostTypeId = 1
),
cte2 AS (
  SELECT
    Id,
    PostTypeId, 
    OwnerUserId, 
    CreationDate, 
    Score, 
    ViewCount, 
    AnswerCount, 
    CommentCount, 
    FavoriteCount,
    ClosedDate, 
    CommunityOwnedDate,
    CloseReason,
    CommunityOwned,
    ROW_NUMBER() OVER (PARTITION BY Id ORDER BY CreationDate DESC) AS rn
  FROM cte1
),
cte3 AS (
  SELECT
    Id,
    PostTypeId,
    OwnerUserId,
    CreationDate,
    Score,
    ViewCount,
    AnswerCount,
    CommentCount,
    FavoriteCount,
    ClosedDate,
    CommunityOwnedDate,
    CloseReason,
    CommunityOwned
  FROM cte2
  WHERE rn = 1
)
SELECT
  p.Id,
  p.PostTypeId,
  p.OwnerUserId,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.AnswerCount,
  p.CommentCount,
  p.FavoriteCount,
  p.ClosedDate,
  p.CommunityOwnedDate,
  p.CloseReason,
  p.CommunityOwned,
  COALESCE(SUM(v.BountyAmount), 0) AS TotalBounty,
  CASE 
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Open'
  END AS PostStatus
FROM cte3 p
LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
GROUP BY
  p.Id,
  p.PostTypeId,
  p.OwnerUserId,
  p.CreationDate,
  p.Score,
  p.ViewCount,
  p.AnswerCount,
  p.CommentCount,
  p.FavoriteCount,
  p.ClosedDate,
  p.CommunityOwnedDate,
  p.CloseReason,
  p.CommunityOwned
ORDER BY TotalBounty DESC;
