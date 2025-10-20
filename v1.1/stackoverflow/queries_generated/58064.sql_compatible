WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.Location,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.CreationDate BETWEEN DATE '2020-01-01' AND DATE '2023-12-31'
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.Reputation, u.Location
),
PostActivity AS (
    SELECT 
        p.OwnerUserId,
        COUNT(DISTINCT ph.Id) AS EditHistoryCount,
        COUNT(DISTINCT pl.RelatedPostId) AS LinkedPosts,
        SUM(CASE WHEN ph.PostHistoryTypeId = 2 THEN 1 ELSE 0 END) AS BodyEdits,
        MAX(p.AnswerCount) AS MaxAnswersPerQuestion
    FROM Posts p
    INNER JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 1
    WHERE p.PostTypeId IN (1,2)
    GROUP BY p.OwnerUserId
),
VoteAnalysis AS (
    SELECT 
        v.UserId,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpvotesGiven,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownvotesGiven,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.PostId END) AS BookmarksCreated
    FROM Votes v
    WHERE v.CreationDate >= DATE '2022-01-01'
    GROUP BY v.UserId
),
BadgeClassSummary AS (
    SELECT 
        b.UserId,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
)
SELECT 
    us.UserId,
    us.Reputation,
    us.Location,
    pa.EditHistoryCount,
    pa.LinkedPosts,
    va.UpvotesGiven,
    va.DownvotesGiven,
    bc.GoldBadges,
    (us.TotalPosts * 2 + us.TotalComments * 0.5 + bc.GoldBadges * 10) AS EngagementScore,
    RANK() OVER (PARTITION BY us.Location ORDER BY us.Reputation DESC) AS LocationRank,
    SUM(us.TotalPosts) OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate)) AS YearlyCohortPosts,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = us.UserId AND p2.Tags LIKE '%<sql>%') AS SQLTagPosts
FROM UserStats us
JOIN PostActivity pa ON us.UserId = pa.OwnerUserId
JOIN VoteAnalysis va ON us.UserId = va.UserId
JOIN BadgeClassSummary bc ON us.UserId = bc.UserId
JOIN Users u ON us.UserId = u.Id
WHERE us.Location IS NOT NULL
  AND pa.MaxAnswersPerQuestion > 5
  AND (bc.GoldBadges > 0 OR bc.SilverBadges > 5)
ORDER BY EngagementScore DESC, LocationRank ASC
LIMIT 100;