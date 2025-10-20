-- {"query": "14075.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 177460, "output_tokens": 76127} 
WITH cte AS (
  SELECT 
    p.Id AS PostId, 
    p.CreationDate, 
    p.OwnerUserId, 
    p.Score, 
    p.AnswerCount, 
    p.CommentCount, 
    p.FavoriteCount, 
    p.ClosedDate, 
    p.CommunityOwnedDate, 
    CASE 
      WHEN p.ClosedDate IS NOT NULL THEN (SELECT Name FROM CloseReasonTypes WHERE Id = CAST(SUBSTRING(ph.Text, 1, CHARINDEX(':', ph.Text) - 1) AS INT)) 
      ELSE NULL 
    END AS CloseReason,
    COALESCE(ph.Comment, '') AS CloseComment,
    COALESCE(CAST(SUBSTRING(ph.Text, CHARINDEX(':', ph.Text) + 2, LEN(ph.Text) - CHARINDEX(':', ph.Text) - 2) AS INT), 0) AS OriginalQuestionId
  FROM Posts p
  LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
  WHERE p.PostTypeId = 1
), cte2 AS (
  SELECT 
    c.PostId, 
    c.CreationDate, 
    c.Score, 
    c.Text, 
    c.UserId, 
    c.UserDisplayName, 
    ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.CreationDate) AS CommentRank
  FROM Comments c
  WHERE c.PostId IN (SELECT PostId FROM cte)
), cte3 AS (
  SELECT 
    p.Id AS PostId, 
    p.PostTypeId, 
    p.AcceptedAnswerId, 
    p.ParentId, 
    p.CreationDate, 
    p.Score, 
    p.ViewCount, 
    p.OwnerUserId, 
    p.OwnerDisplayName, 
    p.LastEditorUserId, 
    p.LastEditorDisplayName, 
    p.LastEditDate, 
    p.LastActivityDate, 
    p.Title, 
    p.Tags, 
    p.AnswerCount, 
    p.CommentCount, 
    p.FavoriteCount, 
    p.ClosedDate, 
    p.CommunityOwnedDate, 
    CASE WHEN p.PostTypeId = 1 THEN (
      SELECT TOP 1 ph.Text 
      FROM PostHistory ph 
      WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 2
      ORDER BY ph.CreationDate
    ) ELSE p.Body END AS Body,
    (
      SELECT COUNT(*) 
      FROM Votes v 
      WHERE v.PostId = p.Id AND v.VoteTypeId = 2
    ) AS UpVotes,
    (
      SELECT COUNT(*) 
      FROM Votes v 
      WHERE v.PostId = p.Id AND v.VoteTypeId = 3
    ) AS DownVotes,
    (
      SELECT COUNT(*) 
      FROM Votes v 
      WHERE v.PostId = p.Id AND v.VoteTypeId = 5
    ) AS FavoriteVotes,
    CASE WHEN p.ParentId IS NOT NULL THEN (
      SELECT p2.OwnerUserId 
      FROM Posts p2 
      WHERE p2.Id = p.ParentId
    ) ELSE NULL END AS ParentOwnerUserId,
    CASE WHEN p.ParentId IS NOT NULL THEN (
      SELECT p2.OwnerDisplayName 
      FROM Posts p2 
      WHERE p2.Id = p.ParentId
    ) ELSE NULL END AS ParentOwnerDisplayName,
    CASE WHEN p.ParentId IS NOT NULL THEN (
      SELECT p2.Score 
      FROM Posts p2 
      WHERE p2.Id = p.ParentId
    ) ELSE NULL END AS ParentScore,
    CASE WHEN p.ParentId IS NOT NULL THEN (
      SELECT p2.ViewCount 
      FROM Posts p2 
      WHERE p2.Id = p.ParentId
    ) ELSE NULL END AS ParentViewCount,
    CASE WHEN p.ParentId IS NOT NULL THEN (
      SELECT p2.AnswerCount 
      FROM Posts p2 
      WHERE p2.Id = p.ParentId
    ) ELSE NULL END AS ParentAnswerCount,
    CASE WHEN p.ParentId IS NOT NULL THEN (
      SELECT p2.CommentCount 
      FROM Posts p2 
      WHERE p2.Id = p.ParentId
    ) ELSE NULL END AS ParentCommentCount,
    CASE WHEN p.ParentId IS NOT NULL THEN (
      SELECT p2.FavoriteCount 
      FROM Posts p2 
      WHERE p2.Id = p.ParentId
    ) ELSE NULL END AS ParentFavoriteCount
  FROM Posts p
)
SELECT 
  cte3.PostId, 
  cte3.PostTypeId, 
  cte3.AcceptedAnswerId, 
  cte3.ParentId, 
  cte3.CreationDate, 
  cte3.Score, 
  cte3.ViewCount, 
  cte3.OwnerUserId, 
  cte3.OwnerDisplayName, 
  cte3.LastEditorUserId, 
  cte3.LastEditorDisplayName, 
  cte3.LastEditDate, 
  cte3.LastActivityDate, 
  cte3.Title, 
  cte3.Tags, 
  cte3.AnswerCount, 
  cte3.CommentCount, 
  cte3.FavoriteCount, 
  cte3.ClosedDate, 
  cte3.CommunityOwnedDate, 
  cte3.Body, 
  cte3.UpVotes, 
  cte3.DownVotes, 
  cte3.FavoriteVotes, 
  cte3.ParentOwnerUserId, 
  cte3.ParentOwnerDisplayName, 
  cte3.ParentScore, 
  cte3.ParentViewCount, 
  cte3.ParentAnswerCount, 
  cte3.ParentCommentCount, 
  cte3.ParentFavoriteCount, 
  cte.CloseReason, 
  cte.CloseComment, 
  cte.OriginalQuestionId, 
  cte2.CommentRank, 
  cte2.Score AS CommentScore, 
  cte2.Text AS CommentText, 
  cte2.UserId AS CommentUserId, 
  cte2.UserDisplayName AS CommentUserDisplayName
FROM cte3
LEFT JOIN cte ON cte3.PostId = cte.PostId
LEFT JOIN cte2 ON cte3.PostId = cte2.PostId
ORDER BY cte3.PostId, cte2.CommentRank;