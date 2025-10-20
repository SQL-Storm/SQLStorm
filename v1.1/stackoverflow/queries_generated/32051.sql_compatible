SELECT 
    u.id AS UserId,
    u.displayname,
    p.OwnerUserId AS PostOwnerUserId,
    p.PostCount,
    p.TotalScore,
    p.TotalViews,
    c.CommentCount,
    v.VoteCount,
    b.BadgeCount
FROM Users u
JOIN (
    SELECT OwnerUserId, COUNT(id) AS PostCount, SUM(Score) AS TotalScore, SUM(ViewCount) AS TotalViews
    FROM Posts
    WHERE PostTypeId = 1
    GROUP BY OwnerUserId
) p ON u.id = p.OwnerUserId
LEFT JOIN (
    SELECT PostId, COUNT(id) AS CommentCount
    FROM Comments
    GROUP BY PostId
) c ON p.OwnerUserId = c.PostId
LEFT JOIN (
    SELECT PostId, COUNT(id) AS VoteCount
    FROM Votes
    WHERE VoteTypeId IN (2, 3)
    GROUP BY PostId
) v ON p.OwnerUserId = v.PostId
LEFT JOIN (
    SELECT UserId, COUNT(id) AS BadgeCount
    FROM Badges
    GROUP BY UserId
) b ON u.id = b.UserId
WHERE p.TotalScore > 100
GROUP BY
    u.id,
    u.displayname,
    p.OwnerUserId,
    p.PostCount,
    p.TotalScore,
    p.TotalViews,
    c.CommentCount,
    v.VoteCount,
    b.BadgeCount
ORDER BY
    p.TotalScore DESC,
    p.PostCount DESC
LIMIT 10;