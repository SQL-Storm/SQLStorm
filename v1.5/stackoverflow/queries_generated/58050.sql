-- {"query": "58050.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1468} 

WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        AVG(p.Score) OVER (PARTITION BY u.Location) AS AvgLocationScore,
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
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.CreationDate BETWEEN '2020-01-01' AND '2023-12-31'
    LEFT JOIN Comments c ON c.UserId = u.Id AND c.CreationDate BETWEEN '2020-01-01' AND '2023-12-31'
    LEFT JOIN Votes v ON v.UserId = u.Id AND v.CreationDate BETWEEN '2020-01-01' AND '2023-12-31'
    LEFT JOIN Badges b ON b.UserId = u.Id AND b.Date BETWEEN '2020-01-01' AND '2023-12-31'
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id AND ph.CreationDate BETWEEN '2020-01-01' AND '2023-12-31'
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
    HAVING COUNT(p.Id) > 50 OR COUNT(c.Id) > 100
)
SELECT 
    UserId,
    DisplayName,
    Reputation,
    Location,
    TotalPosts,
    QuestionsAsked,
    AnswersProvided,
    AvgLocationScore,
    AcceptedAnswers,
    TotalComments,
    UpvotesReceived,
    DownvotesReceived,
    TotalBadges,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    PostEdits,
    PostClosures,
    RANK() OVER (ORDER BY (QuestionsAsked * 2 + AnswersProvided + AcceptedAnswers * 5 + UpvotesReceived - DownvotesReceived + TotalBadges * 3 + PostEdits) DESC) AS EngagementRank
FROM UserStats
ORDER BY EngagementRank, Reputation DESC
LIMIT 100;
