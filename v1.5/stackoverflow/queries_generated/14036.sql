-- {"query": "14036.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 86395, "output_tokens": 36781} 
WITH CTE1 AS (
  SELECT p.Id, p.PostTypeId, p.AnswerCount, p.CommentCount, p.Score, p.ViewCount, p.FavoriteCount, p.CreationDate, u.Reputation, u.UpVotes, u.DownVotes, u.Views
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
),
CTE2 AS (
  SELECT p.Id, p.AcceptedAnswerId, p.ParentId, p.Title, p.Tags, ph.PostHistoryTypeId, ph.CreationDate AS EditDate, ph.UserId, ph.Comment
  FROM Posts p
  JOIN PostHistory ph ON p.Id = ph.PostId
  WHERE ph.PostHistoryTypeId IN (4, 5, 6)
)
SELECT
  CTE1.Id,
  CTE1.PostTypeId,
  CTE1.AnswerCount,
  CTE1.CommentCount,
  CTE1.Score,
  CTE1.ViewCount,
  CTE1.FavoriteCount,
  CTE1.CreationDate,
  CTE1.Reputation,
  CTE1.UpVotes,
  CTE1.DownVotes,
  CTE1.Views,
  CTE2.AcceptedAnswerId,
  CTE2.ParentId,
  CTE2.Title,
  CTE2.Tags,
  CTE2.PostHistoryTypeId,
  CTE2.EditDate,
  CTE2.UserId,
  CTE2.Comment,
  CASE
    WHEN CTE2.PostHistoryTypeId = 4 THEN 'Title Edit'
    WHEN CTE2.PostHistoryTypeId = 5 THEN 'Body Edit'
    WHEN CTE2.PostHistoryTypeId = 6 THEN 'Tag Edit'
  END AS EditType
FROM CTE1
LEFT JOIN CTE2 ON CTE1.Id = CTE2.Id
ORDER BY CTE1.CreationDate DESC, CTE2.EditDate DESC;