
SELECT u.DisplayName, COUNT(p.Id) AS PostCount
FROM Users u
JOIN Posts p ON u.Id = p.OwnerUserId
WHERE u.Reputation > 1000
GROUP BY u.DisplayName, u.Id
ORDER BY PostCount DESC
LIMIT 10;
