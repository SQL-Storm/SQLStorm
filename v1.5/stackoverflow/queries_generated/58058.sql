-- {"query": "58058.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1012} 

WITH HighRepUsers AS (
    SELECT Id, DisplayName, Reputation
    FROM Users
    WHERE Reputation > 10000
), UserPosts AS (
    SELECT 
        p.Id AS PostId, 
        p.OwnerUserId, 
        p.Title, 
        p.Score, 
        p.AnswerCount, 
        p.Tags,
        (SELECT AVG(Score) FROM Posts WHERE OwnerUserId = p.OwnerUserId) AS AvgUserPostScore
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL
), PostVotes AS (
    SELECT 
        PostId, 
        COUNT(*) AS TotalUpvotes,
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes
    FROM Votes
    GROUP BY PostId
), GoldBadgeUsers AS (
    SELECT 
        UserId, 
        COUNT(*) AS GoldBadges
    FROM Badges
    WHERE Class = 1
    GROUP BY UserId
)
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    up.PostId,
    up.Title,
    up.AvgUserPostScore,
    pv.TotalUpvotes,
    pv.Upvotes,
    gb.GoldBadges,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = up.PostId AND c.Score > 5) AS HighScoreComments,
    RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
    ph.CreationDate AS LastCloseDate
FROM HighRepUsers u
JOIN UserPosts up ON u.Id = up.OwnerUserId
LEFT JOIN PostVotes pv ON up.PostId = pv.PostId
LEFT JOIN GoldBadgeUsers gb ON u.Id = gb.UserId
LEFT JOIN (
    SELECT 
        PostId, 
        MAX(CreationDate) AS CreationDate 
    FROM PostHistory 
    WHERE PostHistoryTypeId = 10 
    GROUP BY PostId
) ph ON up.PostId = ph.PostId
WHERE up.AnswerCount > 5 AND up.Score > 50
ORDER BY pv.Upvotes DESC, u.Reputation DESC
LIMIT 100;
