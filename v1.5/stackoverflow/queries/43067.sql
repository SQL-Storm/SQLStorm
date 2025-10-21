SELECT 
    U.DisplayName,
    U.Reputation,
    COUNT(DISTINCT P.Id) AS TotalPosts,
    SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    AVG(P.Score) AS AverageScore,
    MAX(B.Date) AS LastBadgeEarned,
    (SELECT COUNT(*) FROM Badges WHERE UserId = U.Id AND Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges WHERE UserId = U.Id AND Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges WHERE UserId = U.Id AND Class = 3) AS BronzeBadges,
    PH.TotalEdits,
    C.TotalComments,
    V.TotalVotes
FROM 
    Users AS U
LEFT JOIN 
    Posts AS P ON U.Id = P.OwnerUserId
LEFT JOIN 
    (
        SELECT UserId, COUNT(*) AS TotalEdits
        FROM PostHistory
        WHERE PostHistoryTypeId IN (4, 5, 6)
        GROUP BY UserId
    ) AS PH ON U.Id = PH.UserId
LEFT JOIN 
    (
        SELECT UserId, COUNT(*) AS TotalComments
        FROM Comments
        GROUP BY UserId
    ) AS C ON U.Id = C.UserId
LEFT JOIN 
    (
        SELECT UserId, COUNT(*) AS TotalVotes
        FROM Votes
        GROUP BY UserId
    ) AS V ON U.Id = V.UserId
LEFT JOIN 
    Badges AS B ON U.Id = B.UserId
WHERE 
    U.Reputation > 1000
GROUP BY 
    U.Id,
    U.DisplayName,
    U.Reputation,
    PH.TotalEdits,
    C.TotalComments,
    V.TotalVotes,
    B.Date
ORDER BY 
    TotalPosts DESC,
    TotalAnswers DESC,
    AverageScore DESC
LIMIT 100;