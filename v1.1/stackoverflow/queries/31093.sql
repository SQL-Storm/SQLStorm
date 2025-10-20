WITH UserActivity AS (
    SELECT u.Id AS UserId, 
           u.DisplayName, 
           COUNT(DISTINCT p.Id) AS TotalPosts, 
           SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions, 
           SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers, 
           SUM(CASE WHEN p.PostTypeId IN (4, 5) THEN 1 ELSE 0 END) AS TagWikis,
           COALESCE(SUM(c.Score), 0) AS TotalCommentScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON p.Id = c.PostId
    GROUP BY u.Id, u.DisplayName
),
UserVotes AS (
    SELECT v.UserId, 
           COUNT(DISTINCT v.PostId) AS TotalVotes, 
           SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes, 
           SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY v.UserId
),
FinalReport AS (
    SELECT ua.UserId, 
           ua.DisplayName, 
           ua.TotalPosts, 
           ua.Questions, 
           ua.Answers, 
           ua.TagWikis, 
           ua.TotalCommentScore, 
           COALESCE(uv.TotalVotes, 0) AS TotalVotes, 
           COALESCE(uv.UpVotes, 0) AS UpVotes, 
           COALESCE(uv.DownVotes, 0) AS DownVotes,
           (ua.TotalPosts + COALESCE(uv.TotalVotes, 0)) AS CombinedActivityScore
    FROM UserActivity ua
    LEFT JOIN UserVotes uv ON ua.UserId = uv.UserId
    GROUP BY ua.UserId, ua.DisplayName, ua.TotalPosts, ua.Questions, ua.Answers, ua.TagWikis, ua.TotalCommentScore, uv.TotalVotes, uv.UpVotes, uv.DownVotes
)
SELECT UserId,
       DisplayName,
       TotalPosts,
       Questions,
       Answers,
       TagWikis,
       TotalCommentScore,
       TotalVotes,
       UpVotes,
       DownVotes,
       CombinedActivityScore
FROM FinalReport
WHERE CombinedActivityScore > 10
ORDER BY CombinedActivityScore DESC
LIMIT 25;