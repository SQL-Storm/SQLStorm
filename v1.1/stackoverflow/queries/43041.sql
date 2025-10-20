WITH ActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, u.Location, COUNT(p.Id) AS PostsCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.LastAccessDate > DATE '2024-10-01' - INTERVAL '6' MONTH
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
),
TopQuestions AS (
    SELECT p.Id, p.Title, p.ViewCount, p.Score, p.Tags, u.Id AS OwnerId, u.DisplayName AS OwnerName
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 AND p.Score > 100
    ORDER BY p.ViewCount DESC
    LIMIT 100
),
RecentComments AS (
    SELECT c.PostId, COUNT(c.Id) AS CommentCount, MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    WHERE c.CreationDate > DATE '2024-10-01' - INTERVAL '1' MONTH
    GROUP BY c.PostId
)
SELECT 
    au.DisplayName,
    au.Reputation,
    tq.Title AS TopQuestionTitle,
    tq.ViewCount,
    tq.Score,
    rc.CommentCount,
    rc.LastCommentDate
FROM ActiveUsers au
JOIN TopQuestions tq ON au.Id = tq.OwnerId
JOIN RecentComments rc ON tq.Id = rc.PostId
GROUP BY
    au.Id,
    au.DisplayName,
    au.Reputation,
    au.Location,
    au.PostsCount,
    tq.Id,
    tq.Title,
    tq.ViewCount,
    tq.Score,
    tq.Tags,
    tq.OwnerId,
    tq.OwnerName,
    rc.PostId,
    rc.CommentCount,
    rc.LastCommentDate
ORDER BY au.Reputation DESC, rc.CommentCount DESC;