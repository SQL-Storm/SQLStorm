SELECT 
    U.DisplayName,
    U.Reputation,
    COUNT(DISTINCT P.Id) AS TotalPosts,
    SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    SUM(CASE WHEN P.Score > 10 THEN 1 ELSE 0 END) AS HighScoringPosts,
    AVG(P.Score) AS AvgScore,
    MAX(PH.CreationDate) AS LastActivityDate,
    (SELECT COUNT(*) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Comments C WHERE C.UserId = U.Id) AS TotalComments,
    -- build comma-separated distinct tag list for compatibility
    (
      SELECT STRING_AGG(tagname, ',') FROM (
        SELECT DISTINCT T2.TagName AS tagname
        FROM Tags T2
        JOIN Posts P2 ON P2.Tags LIKE '%' || '<' || T2.TagName || '>' || '%'
        WHERE P2.OwnerUserId = U.Id
      ) dt
    ) AS FrequentTags
FROM 
    Users U
LEFT JOIN 
    Posts P ON U.Id = P.OwnerUserId
LEFT JOIN 
    PostHistory PH ON P.Id = PH.PostId
WHERE 
    U.Reputation > 1000
    AND P.CreationDate >= DATE_TRUNC('month', (CAST('2024-10-01' AS DATE) - INTERVAL '6 months'))
GROUP BY 
    U.Id, U.DisplayName, U.Reputation
HAVING 
    COUNT(DISTINCT P.Id) > 10
ORDER BY 
    AvgScore DESC, TotalPosts DESC
LIMIT 10;