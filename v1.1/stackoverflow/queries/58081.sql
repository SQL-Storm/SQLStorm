WITH UserBadges AS (
    SELECT UserId, Class, COUNT(*) AS BadgeCount
    FROM Badges
    GROUP BY UserId, Class
), PostStats AS (
    SELECT OwnerUserId, SUM(ViewCount) AS TotalViews, AVG(Score) AS AvgScore
    FROM Posts
    WHERE PostTypeId = 1 AND CreationDate >= DATE '2022-01-01'
    GROUP BY OwnerUserId
), CommentScores AS (
    SELECT UserId, SUM(Score) AS TotalCommentScore
    FROM Comments
    WHERE CreationDate BETWEEN DATE '2022-01-01' AND DATE '2023-01-01'
    GROUP BY UserId
), VoteCounts AS (
    SELECT UserId, VoteTypeId, COUNT(*) AS VoteTypeCount
    FROM Votes
    WHERE CreationDate >= DATE '2020-01-01'
    GROUP BY UserId, VoteTypeId
)
SELECT 
    u.Id AS UserId,
    u.Reputation,
    u.UpVotes - u.DownVotes AS NetVotes,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId IN (10, 35, 36)) AS SpecialEvents,
    COALESCE(ub_gold.BadgeCount, 0) AS GoldBadges,
    COALESCE(ub_silver.BadgeCount, 0) AS SilverBadges,
    ps.TotalViews,
    ps.AvgScore,
    cs.TotalCommentScore,
    COALESCE(vc_up.VoteTypeCount, 0) AS UpvotesGiven,
    COALESCE(vc_close.VoteTypeCount, 0) AS CloseVotesGiven,
    RANK() OVER (ORDER BY (COALESCE(ub_gold.BadgeCount,0) * 3 + COALESCE(ub_silver.BadgeCount,0) * 2) DESC) AS BadgeRank
FROM Users u
LEFT JOIN UserBadges ub_gold ON u.Id = ub_gold.UserId AND ub_gold.Class = 1
LEFT JOIN UserBadges ub_silver ON u.Id = ub_silver.UserId AND ub_silver.Class = 2
LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
LEFT JOIN CommentScores cs ON u.Id = cs.UserId
LEFT JOIN VoteCounts vc_up ON u.Id = vc_up.UserId AND vc_up.VoteTypeId = 2
LEFT JOIN VoteCounts vc_close ON u.Id = vc_close.UserId AND vc_close.VoteTypeId = 6
WHERE u.Reputation > 10000
  AND u.CreationDate < DATE '2023-01-01'
  AND EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id AND p.AnswerCount > 5)
GROUP BY
    u.Id,
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    ps.TotalViews,
    ps.AvgScore,
    cs.TotalCommentScore,
    ub_gold.BadgeCount,
    ub_silver.BadgeCount,
    vc_up.VoteTypeCount,
    vc_close.VoteTypeCount
HAVING COALESCE(ub_gold.BadgeCount, 0) > 5 OR COALESCE(ub_silver.BadgeCount, 0) > 10
ORDER BY ps.TotalViews DESC NULLS LAST, ps.AvgScore DESC NULLS LAST, NetVotes DESC
LIMIT 100;