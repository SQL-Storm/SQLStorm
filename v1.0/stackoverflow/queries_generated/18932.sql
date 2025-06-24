SELECT p.Title, u.DisplayName, COUNT(c.Id) AS CommentCount, SUM(v.VoteTypeId = 2) AS UpVoteCount
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
WHERE p.PostTypeId = 1 -- Considering only Questions
GROUP BY p.Id, u.DisplayName
ORDER BY UpVoteCount DESC, CommentCount DESC
LIMIT 10;
