WITH RankedUsers AS (
    SELECT Id, Reputation,
           ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS Rank
    FROM Users
),
TopUsers AS (
    SELECT ru.Id, u.DisplayName, ru.Reputation
    FROM RankedUsers ru
    JOIN Users u ON u.Id = ru.Id
    WHERE ru.Rank <= 100
)
SELECT u.DisplayName, u.Reputation, COUNT(p.Id) AS TotalPosts
FROM TopUsers u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
GROUP BY u.Id, u.DisplayName, u.Reputation
ORDER BY TotalPosts DESC;