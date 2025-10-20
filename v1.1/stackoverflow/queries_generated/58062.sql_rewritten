-- {"query": "58062.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1978} 
SELECT 
    U.Id AS UserId, 
    U.DisplayName, 
    U.Reputation, 
    COUNT(DISTINCT P.Id) AS TotalPosts, 
    SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS Questions, 
    SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS Answers, 
    COUNT(DISTINCT C.Id) AS TotalComments, 
    SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, 
    SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes, 
    COUNT(DISTINCT B.Id) AS TotalBadges, 
    SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges, 
    SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges, 
    SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges, 
    (SELECT AVG(Score) FROM Posts WHERE OwnerUserId = U.Id) AS AvgPostScore, 
    COUNT(DISTINCT PH.Id) AS PostEdits, 
    SUM(P.ViewCount) AS TotalViews 
FROM 
    Users U 
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId 
    LEFT JOIN Comments C ON U.Id = C.UserId 
    LEFT JOIN Votes V ON U.Id = V.UserId 
    LEFT JOIN Badges B ON U.Id = B.UserId 
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId AND PH.PostHistoryTypeId IN (4,5,6,10) 
WHERE 
    U.Reputation > 1000 
    AND U.CreationDate >= '2010-01-01' 
GROUP BY 
    U.Id, U.DisplayName, U.Reputation 
HAVING 
    COUNT(DISTINCT P.Id) >= 10 
    AND COUNT(DISTINCT B.Id) >= 5 
ORDER BY 
    U.Reputation DESC, 
    TotalViews DESC, 
    TotalPosts DESC 
LIMIT 100;