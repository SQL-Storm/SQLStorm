-- {"query": "32013.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 321} 
SELECT u.Id AS UserId, u.DisplayName, u.Reputation, 
       p.Id AS PostId, p.Title, p.CreationDate AS PostCreation, p.Score, p.ViewCount, p.AnswerCount, 
       b.Name AS BadgeName, b.Date AS BadgeDate, b.Class AS BadgeClass, 
       c.Id AS CommentId, c.Score AS CommentScore, c.Text AS CommentText, 
       ph.Id AS PostHistoryId, ph.CreationDate AS HistoryCreation, ph.PostHistoryTypeId, ph.Comment AS ChangeComment,
       t.TagName
FROM Users u
JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN Comments c ON c.PostId = p.Id AND c.UserId IS NOT NULL
LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.UserId = u.Id
LEFT JOIN Tags t ON ',' || p.Tags || ',' LIKE '%,' || t.TagName || ',%'
WHERE p.PostTypeId IN (1, 2)
  AND p.CreationDate BETWEEN cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year' AND cast('2024-10-01 12:34:56' as timestamp)
  AND u.Reputation > 500
  AND EXISTS (
    SELECT 1 
    FROM Votes v 
    WHERE v.PostId = p.Id 
      AND v.VoteTypeId = 2 -- UpMod (upvote)
  )
ORDER BY u.Reputation DESC, p.CreationDate DESC, b.Class ASC
LIMIT 1000;