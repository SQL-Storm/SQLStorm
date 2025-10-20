WITH ActiveUsers AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.Reputation, 
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS TotalVotes,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Comments c ON u.Id = c.UserId AND c.CreationDate BETWEEN DATE '2020-01-01' AND DATE '2023-12-31'
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Date > DATE '2022-01-01'
    WHERE u.Reputation > 10000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostStats AS (
    SELECT 
        p.OwnerUserId,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.AnswerCount) AS MaxAnswers,
        SUM(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 ELSE 0 END) AS TitleEdits
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4,5,6)
    WHERE p.Tags LIKE '%<sql><performance>%'
    GROUP BY p.OwnerUserId
)
SELECT 
    au.DisplayName,
    au.Reputation,
    au.TotalPosts,
    au.TotalComments,
    au.TotalVotes,
    au.GoldBadges,
    ps.AvgPostScore,
    ps.MaxAnswers,
    ps.TitleEdits,
    RANK() OVER (ORDER BY (au.TotalPosts * 0.3 + au.TotalComments * 0.2 + au.GoldBadges * 0.5) DESC) AS ActivityRank
FROM ActiveUsers au
JOIN PostStats ps ON au.Id = ps.OwnerUserId
WHERE au.TotalPosts > 50 AND ps.MaxAnswers > 10
ORDER BY ActivityRank, au.Reputation DESC
LIMIT 100;