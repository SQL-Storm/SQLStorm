SELECT p.Title, p.CreationDate, u.DisplayName AS OwnerDisplayName, 
       COUNT(c.Id) AS CommentCount, AVG(v.BountyAmount) AS AverageBounty
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
GROUP BY p.Id, u.DisplayName
ORDER BY p.CreationDate DESC
LIMIT 10;
