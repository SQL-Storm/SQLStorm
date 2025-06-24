
SELECT 
    COUNT(*) AS TotalUsers,
    AVG(Reputation) AS AverageReputation
FROM 
    Users
GROUP BY 
    Reputation;
