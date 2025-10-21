-- {"query": "58006.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 2323} 

WITH HighRepUsers AS (
    SELECT Id, DisplayName, Reputation, CreationDate
    FROM Users
    WHERE Reputation > 100000 AND CreationDate >= '2010-01-01'
), 
UserPosts AS (
    SELECT 
        p.Id AS PostId, 
        p.OwnerUserId, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.AnswerCount, 
        p.CommentCount, 
        p.FavoriteCount,
        ph.CloseEvents
    FROM Posts p
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS CloseEvents
        FROM PostHistory
        WHERE PostHistoryTypeId = 10
        GROUP BY PostId
    ) ph ON p.Id = ph.PostId
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IN (SELECT Id FROM HighRepUsers)
),
PostVotes AS (
    SELECT 
        PostId,
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM Votes
    WHERE CreationDate >= '2020-01-01'
    GROUP BY PostId
),
UserBadges AS (
    SELECT 
        UserId, 
        COUNT(*) FILTER (WHERE Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE Class = 2) AS SilverBadges
    FROM Badges
    WHERE Date >= '2020-01-01'
    GROUP BY UserId
)
SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    COUNT(p.PostId) AS TotalQuestions,
    AVG(p.Score) AS AvgQuestionScore,
    SUM(p.AnswerCount) AS TotalAnswersGenerated,
    SUM(p.CloseEvents) AS TotalClosures,
    SUM(v.Upvotes) AS TotalUpvotes,
    SUM(v.Downvotes) AS TotalDownvotes,
    COALESCE(b.GoldBadges, 0) AS RecentGoldBadges,
    RANK() OVER (ORDER BY SUM(v.Upvotes - v.Downvotes) DESC) AS EngagementRank
FROM HighRepUsers u
LEFT JOIN UserPosts p ON u.Id = p.OwnerUserId
LEFT JOIN PostVotes v ON p.PostId = v.PostId
LEFT JOIN UserBadges b ON u.Id = b.UserId
GROUP BY u.Id, u.DisplayName, u.Reputation, b.GoldBadges
ORDER BY EngagementRank, u.Reputation DESC
LIMIT 50;
