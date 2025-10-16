WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersProvided
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.OwnerUserId != -1
    GROUP BY u.Id
),
CommentStats AS (
    SELECT 
        p.OwnerUserId AS UserId,
        AVG(c.Score) AS AvgCommentScore,
        COUNT(DISTINCT c.Id) AS TotalComments
    FROM Posts p
    JOIN Comments c ON p.Id = c.PostId
    WHERE p.OwnerUserId != -1
    GROUP BY p.OwnerUserId
),
VoteAnalysis AS (
    SELECT 
        v.UserId,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpvotesReceived,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 8 THEN v.Id END) AS BountiesStarted,
        SUM(v.BountyAmount) AS TotalBountyAmount
    FROM Votes v
    JOIN Posts p ON v.PostId = p.Id AND p.OwnerUserId != -1
    GROUP BY v.UserId
)
SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    us.GoldBadges,
    us.SilverBadges,
    us.TotalPosts,
    cs.AvgCommentScore,
    cs.TotalComments,
    va.UpvotesReceived,
    va.BountiesStarted,
    va.TotalBountyAmount,
    RANK() OVER (ORDER BY u.Reputation DESC) AS GlobalRank,
    DENSE_RANK() OVER (PARTITION BY us.GoldBadges ORDER BY u.Reputation DESC) AS RankByGoldBadges,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND EXISTS (
        SELECT 1 FROM Comments c2 WHERE c2.PostId = p2.Id AND c2.UserId = u.Id
    )) AS SelfCommentedPosts,
    COALESCE(STRING_AGG(DISTINCT SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), ', '), '') AS TagHistory,
    COUNT(DISTINCT ph.Id) AS BodyEdits
FROM Users u
LEFT JOIN UserStats us ON u.Id = us.UserId
LEFT JOIN CommentStats cs ON u.Id = cs.UserId
LEFT JOIN VoteAnalysis va ON u.Id = va.UserId
LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (2,5,8)
WHERE u.Reputation > 1000
    AND COALESCE(us.QuestionsAsked, 0) > 10
    AND (COALESCE(us.AnswersProvided, 0) > 50 OR COALESCE(va.UpvotesReceived, 0) > 200)
    AND p.CreationDate BETWEEN DATE '2010-01-01' AND DATE '2023-12-31'
GROUP BY 
    u.Id, u.DisplayName, u.Reputation, 
    us.GoldBadges, us.SilverBadges, us.TotalPosts, us.QuestionsAsked, us.AnswersProvided,
    cs.AvgCommentScore, cs.TotalComments,
    va.UpvotesReceived, va.BountiesStarted, va.TotalBountyAmount,
    p.Tags
ORDER BY GlobalRank, TotalPosts DESC, BountiesStarted DESC
LIMIT 100;