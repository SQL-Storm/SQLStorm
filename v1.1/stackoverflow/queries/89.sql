-- {"query": "89.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 326} 
WITH RankedUsers AS (
    SELECT Id, DisplayName, Reputation, 
           ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS Rank
    FROM Users
),
TopUsers AS (
    SELECT Id, DisplayName, Reputation, Rank
    FROM RankedUsers
    WHERE Rank <= 100
),
UserAnswers AS (
    SELECT OwnerUserId, COUNT(Id) AS AnswerCount
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY OwnerUserId
),
UserUpvotes AS (
    SELECT UserId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount
    FROM Votes
    GROUP BY UserId
),
UserBadgeInfos AS (
    SELECT u.Id, COUNT(b.Id) AS TotalBadges, SUM(b.Class) AS GoldBadges, 
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges, 
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id
)
SELECT tu.DisplayName, tu.Reputation, ua.AnswerCount, ubi.TotalBadges, 
       ubi.GoldBadges, ubi.SilverBadges, ubi.BronzeBadges
FROM TopUsers tu
LEFT JOIN UserAnswers ua ON tu.Id = ua.OwnerUserId
LEFT JOIN UserBadgeInfos ubi ON tu.Id = ubi.Id
LEFT JOIN UserUpvotes uu ON tu.Id = uu.UserId;