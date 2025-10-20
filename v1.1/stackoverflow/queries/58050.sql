WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        -- compute average location score by aggregating posts per user location
        CASE WHEN COUNT(p.Id) > 0 THEN SUM(p.Score) * 1.0 / COUNT(p.Id) ELSE NULL END AS AvgLocationScore,
        (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.AcceptedAnswerId IS NOT NULL) AS AcceptedAnswers,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpvotesReceived,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownvotesReceived,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        COUNT(DISTINCT ph.Id) AS PostEdits,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) AS PostClosures
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.CreationDate >= DATE '2020-01-01' AND p.CreationDate < DATE '2024-01-01'
    LEFT JOIN Comments c ON c.UserId = u.Id AND c.CreationDate >= DATE '2020-01-01' AND c.CreationDate < DATE '2024-01-01'
    LEFT JOIN Votes v ON v.UserId = u.Id AND v.CreationDate >= DATE '2020-01-01' AND v.CreationDate < DATE '2024-01-01'
    LEFT JOIN Badges b ON b.UserId = u.Id AND b.Date >= DATE '2020-01-01' AND b.Date < DATE '2024-01-01'
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id AND ph.CreationDate >= DATE '2020-01-01' AND ph.CreationDate < DATE '2024-01-01'
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
    HAVING COUNT(p.Id) > 50 OR COUNT(c.Id) > 100
),
LocationAvg AS (
    -- compute average post score per location across users' posts in the same date range
    SELECT
        u.Location,
        AVG(p.Score) AS AvgLocationScore
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.CreationDate >= DATE '2020-01-01' AND p.CreationDate < DATE '2024-01-01'
    GROUP BY u.Location
)
SELECT 
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.Location,
    us.TotalPosts,
    us.QuestionsAsked,
    us.AnswersProvided,
    COALESCE(la.AvgLocationScore, us.AvgLocationScore) AS AvgLocationScore,
    us.AcceptedAnswers,
    us.TotalComments,
    us.UpvotesReceived,
    us.DownvotesReceived,
    us.TotalBadges,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.PostEdits,
    us.PostClosures,
    RANK() OVER (ORDER BY (us.QuestionsAsked * 2 + us.AnswersProvided + us.AcceptedAnswers * 5 + us.UpvotesReceived - us.DownvotesReceived + us.TotalBadges * 3 + us.PostEdits) DESC, us.Reputation DESC) AS EngagementRank
FROM UserStats us
LEFT JOIN LocationAvg la ON (us.Location = la.Location)
ORDER BY EngagementRank, Reputation DESC
LIMIT 100;