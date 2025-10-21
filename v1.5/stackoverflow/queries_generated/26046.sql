-- {"query": "26046.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 566} 

WITH TopUsers AS (
  SELECT 
    u.Id, 
    u.DisplayName, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, 
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId
  LEFT JOIN Votes v ON p.Id = v.PostId
  GROUP BY u.Id, u.DisplayName
  HAVING SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 1000
),
TopPosts AS (
  SELECT 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS RowNum
  FROM Posts p
  WHERE p.PostTypeId = 1 AND p.Score > 100
),
PostHistoryCTE AS (
  SELECT 
    ph.PostId, 
    ph.PostHistoryTypeId, 
    ph.CreationDate, 
    ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS RowNum
  FROM PostHistory ph
)
SELECT 
  u.DisplayName, 
  u.Reputation, 
  tu.UpVotes, 
  tu.DownVotes, 
  p.Title, 
  p.Score, 
  p.ViewCount, 
  p.AnswerCount, 
  ph.CreationDate AS LastEditDate, 
  ph.PostHistoryTypeId, 
  pt.Name AS PostTypeName, 
  CASE 
    WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    ELSE 'Open'
  END AS PostStatus,
  STRING_AGG(t.TagName, ', ') AS Tags
FROM Users u
JOIN TopUsers tu ON u.Id = tu.Id
JOIN Posts p ON u.Id = p.OwnerUserId
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN PostHistoryCTE ph ON p.Id = ph.PostId AND ph.RowNum = 1
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN Tags t ON pl.RelatedPostId = t.Id
WHERE p.Id IN (SELECT Id FROM TopPosts WHERE RowNum <= 10)
GROUP BY u.DisplayName, u.Reputation, tu.UpVotes, tu.DownVotes, p.Title, p.Score, p.ViewCount, p.AnswerCount, ph.CreationDate, ph.PostHistoryTypeId, pt.Name, p.ClosedDate, p.CommunityOwnedDate
ORDER BY u.Reputation DESC;
