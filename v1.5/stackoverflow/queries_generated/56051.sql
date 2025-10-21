-- {"query": "56051.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 378} 

WITH Top10Posts AS (
  SELECT p.Id, p.Score, p.ViewCount, p.Title, u.DisplayName AS OwnerDisplayName
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 AND p.Score > 0
  ORDER BY p.Score DESC
  LIMIT 10
),
Top10Users AS (
  SELECT u.Id, u.DisplayName, u.Reputation, COUNT(p.Id) AS PostCount
  FROM Users u
  JOIN Posts p ON u.Id = p.OwnerUserId
  WHERE p.PostTypeId IN (1, 2)
  GROUP BY u.Id, u.DisplayName, u.Reputation
  ORDER BY u.Reputation DESC
  LIMIT 10
),
PostHistoryStats AS (
  SELECT ph.PostId, COUNT(ph.Id) AS HistoryCount, MAX(ph.CreationDate) AS LastEditDate
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (4, 5, 6)
  GROUP BY ph.PostId
)
SELECT 
  p.Id, 
  p.Score, 
  p.ViewCount, 
  p.Title, 
  u.DisplayName AS OwnerDisplayName, 
  phs.HistoryCount, 
  phs.LastEditDate, 
  v.VoteTypeId, 
  v.UserId AS VoterId, 
  vt.Name AS VoteTypeName
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
JOIN PostHistoryStats phs ON p.Id = phs.PostId
JOIN Votes v ON p.Id = v.PostId
JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
WHERE p.Id IN (SELECT Id FROM Top10Posts) AND u.Id IN (SELECT Id FROM Top10Users)
ORDER BY p.Score DESC, phs.HistoryCount DESC;
