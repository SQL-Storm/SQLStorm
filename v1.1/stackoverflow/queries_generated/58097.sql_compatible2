WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        COUNT(DISTINCT b.Id) AS TotalBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 8)
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class = 1
    WHERE u.Reputation > 10000
    GROUP BY u.Id, u.Reputation
),
PostStats AS (
    SELECT 
        p.OwnerUserId,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.AnswerCount) AS MaxAnswerCount,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS TotalEdits,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TotalClosures,
        STRING_AGG(DISTINCT t.TagName, ', ') AS FrequentTags
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId
    JOIN Tags t ON POSITION(t.TagName IN REPLACE(REPLACE(COALESCE(p.Tags, ''), '><', ','), '<', '')) > 0
    WHERE p.CreationDate >= DATE '2020-01-01' AND p.Score > 50
    GROUP BY p.OwnerUserId
),
BadgeStats AS (
    SELECT 
        UserId,
        SUM(CASE WHEN Name LIKE '%Legendary%' THEN 1 ELSE 0 END) AS LegendaryBadges
    FROM Badges
    WHERE Date >= DATE '2023-01-01'
    GROUP BY UserId
),
VoteStats AS (
    SELECT 
        UserId,
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
        SUM(COALESCE(BountyAmount, 0)) AS TotalBountyAwarded
    FROM Votes
    WHERE CreationDate BETWEEN DATE '2022-01-01' AND DATE '2023-12-31'
    GROUP BY UserId
)
SELECT 
    u.Id,
    u.DisplayName,
    us.Reputation,
    ps.AvgPostScore,
    ps.MaxAnswerCount,
    vs.TotalUpvotes,
    vs.TotalBountyAwarded,
    COALESCE(bs.LegendaryBadges, 0) AS LegendaryBadges,
    ps.FrequentTags,
    RANK() OVER (ORDER BY (us.TotalPosts + us.TotalComments + us.TotalVotes) DESC) AS ActivityRank,
    us.TotalPosts,
    us.TotalComments,
    us.TotalVotes,
    us.TotalBadges,
    ps.TotalEdits,
    ps.TotalClosures
FROM Users u
JOIN UserStats us ON u.Id = us.UserId
JOIN PostStats ps ON u.Id = ps.OwnerUserId
LEFT JOIN BadgeStats bs ON u.Id = bs.UserId
LEFT JOIN VoteStats vs ON u.Id = vs.UserId
WHERE ps.TotalEdits > 10 AND ps.TotalClosures < 5
GROUP BY
    u.Id,
    u.DisplayName,
    us.Reputation,
    ps.AvgPostScore,
    ps.MaxAnswerCount,
    vs.TotalUpvotes,
    vs.TotalBountyAwarded,
    bs.LegendaryBadges,
    ps.FrequentTags,
    us.TotalPosts,
    us.TotalComments,
    us.TotalVotes,
    us.TotalBadges,
    ps.TotalEdits,
    ps.TotalClosures
HAVING AVG(ps.AvgPostScore) > 100 AND SUM(us.TotalBadges) >= 5
ORDER BY ActivityRank, vs.TotalBountyAwardED DESC
LIMIT 100;