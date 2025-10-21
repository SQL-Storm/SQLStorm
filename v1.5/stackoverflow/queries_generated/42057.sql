-- {"query": "42057.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2057, "output_tokens": 337} 

SELECT 
  U.DisplayName,
  P.Title,
  COUNT(DISTINCT V.Id) AS TotalVotes,
  COUNT(DISTINCT C.Id) AS TotalComments,
  SUM(CASE WHEN PH.PostHistoryTypeId IN (2, 5, 24) THEN 1 ELSE 0 END) AS TotalEdits,
  B.Name AS BadgeName
FROM 
  Users U
JOIN 
  Posts P ON U.Id = P.OwnerUserId
LEFT JOIN 
  Votes V ON P.Id = V.PostId
LEFT JOIN 
  Comments C ON P.Id = C.PostId
LEFT JOIN 
  PostHistory PH ON P.Id = PH.PostId
LEFT JOIN 
  Badges B ON U.Id = B.UserId
WHERE 
  P.PostTypeId = 1
  AND V.VoteTypeId IN (2, 3)
  AND PH.PostHistoryTypeId IN (2, 5, 24)
  AND B.Class = 1
GROUP BY 
  U.DisplayName, 
  P.Title, 
  B.Name
HAVING 
  COUNT(DISTINCT V.Id) > 10
  AND COUNT(DISTINCT C.Id) > 5
  AND SUM(CASE WHEN PH.PostHistoryTypeId IN (2, 5, 24) THEN 1 ELSE 0 END) > 3
ORDER BY 
  TotalVotes DESC, 
  TotalComments DESC, 
  TotalEdits DESC
LIMIT 100;
