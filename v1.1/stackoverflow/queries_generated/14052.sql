-- {"query": "14052.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 123755, "output_tokens": 53058} 
WITH cte AS (
  SELECT 
    p.Id, 
    p.CreationDate, 
    p.Score, 
    p.AnswerCount, 
    p.CommentCount, 
    p.FavoriteCount, 
    p.ClosedDate, 
    p.CommunityOwnedDate,
    CASE 
      WHEN p.ClosedDate IS NOT NULL THEN (SELECT Name FROM CloseReasonTypes WHERE Id = CAST(SUBSTRING(ph.Text, CHARINDEX('"', ph.Text) + 1, CHARINDEX('"', ph.Text, CHARINDEX('"', ph.Text) + 1) - CHARINDEX('"', ph.Text) - 1) AS SMALLINT))
      ELSE NULL
    END AS CloseReason
  FROM Posts p
  LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
),
votes_cte AS (
  SELECT 
    v.PostId, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteVotes
  FROM Votes v
  GROUP BY v.PostId
)
SELECT 
  p.Id, 
  p.PostTypeId, 
  p.AcceptedAnswerId, 
  p.ParentId, 
  p.CreationDate, 
  p.Score, 
  p.ViewCount, 
  p.OwnerUserId, 
  p.LastEditDate, 
  p.LastActivityDate, 
  p.Title, 
  REPLACE(REPLACE(p.Tags, '<', ''), '>', '') AS Tags,
  cte.AnswerCount, 
  cte.CommentCount, 
  cte.FavoriteCount, 
  cte.ClosedDate, 
  cte.CommunityOwnedDate,
  cte.CloseReason,
  votes_cte.UpVotes,
  votes_cte.DownVotes,
  votes_cte.FavoriteVotes
FROM Posts p
LEFT JOIN cte ON p.Id = cte.Id
LEFT JOIN votes_cte ON p.Id = votes_cte.PostId
ORDER BY p.CreationDate DESC
OFFSET 0 ROWS
FETCH NEXT 100 ROWS ONLY;