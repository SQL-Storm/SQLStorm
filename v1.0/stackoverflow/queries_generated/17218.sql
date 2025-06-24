SELECT u.DisplayName, p.Title, p.CreationDate, p.Score, c.Text AS CommentText
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
WHERE p.PostTypeId = 1 -- Only questions
ORDER BY p.CreationDate DESC
LIMIT 10;
