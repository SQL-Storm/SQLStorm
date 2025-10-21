WITH cte AS (
    SELECT p.Id AS PostId, p.Title, COUNT(DISTINCT c.UserId) AS NumCommentators
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title
)

SELECT c.PostId, c.Title, c.NumCommentators, vt.Name AS VoteTypeName, vt.Name || ' is interesting' AS Description
FROM cte c
LEFT JOIN Votes v ON c.PostId = v.PostId
LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
WHERE v.CreationDate > (SELECT MAX(CreationDate) FROM Votes)
ORDER BY c.NumCommentators DESC, c.PostId;