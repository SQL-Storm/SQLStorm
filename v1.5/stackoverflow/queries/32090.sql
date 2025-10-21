SELECT u.Id AS UserId,
       u.DisplayName,
       u.Reputation,
       COUNT(DISTINCT p.Id) AS TotalPosts,
       COALESCE(SUM(p.ViewCount), 0) AS TotalViews,
       COALESCE(SUM(p.Score), 0) AS TotalScore,
       COUNT(DISTINCT b.Id) AS TotalBadges
FROM Users AS u
LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
LEFT JOIN Badges AS b ON u.Id = b.UserId
LEFT JOIN (
    SELECT PostId, COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY PostId
) AS c ON p.Id = c.PostId
LEFT JOIN (
    SELECT PostId, COUNT(*) AS AnswerCount
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY PostId
) AS a ON p.Id = a.PostId
LEFT JOIN (
    SELECT PostId, COUNT(*) AS VoteCount,
           SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes
    GROUP BY PostId
) AS v ON p.Id = v.PostId
GROUP BY u.Id, u.DisplayName, u.Reputation
ORDER BY COALESCE(SUM(p.Score), 0) DESC,
         COALESCE(SUM(p.ViewCount), 0) DESC
LIMIT 50;