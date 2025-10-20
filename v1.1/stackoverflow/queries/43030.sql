SELECT 
    U.Id,
    U.DisplayName,
    U.Reputation,
    COUNT(DISTINCT P.Id) AS TotalPosts,
    SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    AVG(P.Score) AS AvgPostScore,
    SUM(P.ViewCount) AS TotalViewCount,
    COUNT(DISTINCT B.Id) AS TotalBadges,
    MAX(B.Date) AS LastBadgeDate,
    COUNT(DISTINCT C.Id) AS TotalComments,
    MAX(PH.CreationDate) AS LastEditDate,
    (SELECT COUNT(*) FROM Votes V1 WHERE V1.UserId = U.Id AND V1.VoteTypeId = 2) AS TotalUpVotesGiven,
    (SELECT COUNT(*) FROM Votes V2 WHERE V2.UserId = U.Id AND V2.VoteTypeId = 3) AS TotalDownVotesGiven
FROM 
    Users U
LEFT JOIN 
    Posts P ON U.Id = P.OwnerUserId
LEFT JOIN 
    Badges B ON U.Id = B.UserId
LEFT JOIN 
    Comments C ON U.Id = C.UserId
LEFT JOIN 
    (
      SELECT PostId, MAX(CreationDate) AS CreationDate
      FROM PostHistory
      WHERE PostHistoryTypeId IN (4, 5, 6)
      GROUP BY PostId
    ) PH ON P.Id = PH.PostId
WHERE 
    U.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
GROUP BY 
    U.Id,
    U.DisplayName,
    U.Reputation
ORDER BY 
    TotalPosts DESC, AvgPostScore DESC
LIMIT 10;