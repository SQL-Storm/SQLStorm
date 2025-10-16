-- {"query": "83.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 182} 
WITH RankedUsers AS (
    SELECT Id, Reputation, ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS Rank
    FROM Users
),
TopUsers AS (
    SELECT Id, Reputation
    FROM RankedUsers
    WHERE Rank <= 100
),
UserPostCounts AS (
    SELECT UserId, COUNT(*) AS PostCount
    FROM Posts
    WHERE OwnerUserId IN (SELECT Id FROM TopUsers)
    GROUP BY UserId
),
UserBadgeCounts AS (
    SELECT UserId, COUNT(*) AS BadgeCount
    FROM Badges
    WHERE UserId IN (SELECT Id FROM TopUsers)
    GROUP BY UserId
)
SELECT U.Id, U.Reputation, UPC.PostCount, UBC.BadgeCount
FROM TopUsers U
JOIN UserPostCounts UPC ON U.Id = UPC.UserId
JOIN UserBadgeCounts UBC ON U.Id = UBC.UserId
ORDER BY U.Reputation DESC;