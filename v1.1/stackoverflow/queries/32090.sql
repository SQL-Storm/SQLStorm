SELECT u.Id AS UserId, u.DisplayName, u.Reputation, 
       COUNT(DISTINCT p.Id) AS TotalPosts, 
       COALESCE(SUM(p.ViewCount), 0) AS TotalViews, 
       COALESCE(SUM(p.Score), 0) AS TotalScore, 
       COUNT(DISTINCT b.Id) AS TotalBadges,
       COALESCE(SUM(c.CommentCount), 0) AS TotalComments,
       COALESCE(SUM(a.AnswerCount), 0) AS TotalAnswers,
       COALESCE(SUM(v.VoteCount), 0) AS TotalVotes,
       COALESCE(SUM(v.UpVotes), 0) AS TotalUpVotes,
       COALESCE(SUM(v.DownVotes), 0) AS TotalDownVotes
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN (
    SELECT PostId, COUNT(*) AS CommentCount 
    FROM Comments 
    GROUP BY PostId
) c ON p.Id = c.PostId
LEFT JOIN (
    SELECT ParentId AS PostId, COUNT(*) AS AnswerCount 
    FROM Posts 
    WHERE PostTypeId = 2
    GROUP BY ParentId
) a ON p.Id = a.PostId
LEFT JOIN (
    SELECT PostId, COUNT(*) AS VoteCount, 
           SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes 
    GROUP BY PostId
) v ON p.Id = v.PostId
GROUP BY u.Id, u.DisplayName, u.Reputation
ORDER BY TotalScore DESC, TotalViews DESC
LIMIT 50;