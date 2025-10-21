WITH TopUsers AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           u.UpVotes,
           u.DownVotes,
           COUNT(DISTINCT b.Id) AS BadgeCount
    FROM Users u
         LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate BETWEEN DATE '2022-01-01' AND DATE '2023-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
    ORDER BY u.Reputation DESC, BadgeCount DESC
    LIMIT 100
),
UserPostStats AS (
    SELECT p.OwnerUserId,
           COUNT(*) AS TotalPosts,
           SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
           SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
           AVG(p.Score) AS AvgScore,
           MAX(p.Score) AS MaxScore
    FROM Posts p
    WHERE p.OwnerUserId IN (SELECT Id FROM TopUsers)
    GROUP BY p.OwnerUserId
),
UserCommentStats AS (
    SELECT c.UserId,
           COUNT(*) AS TotalComments,
           AVG(c.Score) AS AvgCommentScore
    FROM Comments c
    WHERE c.UserId IN (SELECT Id FROM TopUsers)
    GROUP BY c.UserId
)
SELECT tu.DisplayName,
       tu.Reputation,
       ups.TotalPosts,
       ups.TotalQuestions,
       ups.TotalAnswers,
       ups.AvgScore,
       ups.MaxScore,
       ucs.TotalComments,
       ucs.AvgCommentScore,
       tu.BadgeCount
FROM TopUsers tu
     LEFT JOIN UserPostStats ups ON tu.Id = ups.OwnerUserId
     LEFT JOIN UserCommentStats ucs ON tu.Id = ucs.UserId
ORDER BY tu.Reputation DESC, ups.TotalPosts DESC, tu.BadgeCount DESC;