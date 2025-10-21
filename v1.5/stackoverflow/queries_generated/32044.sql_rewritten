-- {"query": "32044.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 313} 
SELECT U.DisplayName, U.Reputation, P.PostTypeId, P.Title, COUNT(DISTINCT V.Id) AS TotalVotes, 
       AVG(B.ReputationChange) AS AvgReputationChange, COUNT(DISTINCT A.Id) AS AnswerCount, 
       STRING_AGG(DISTINCT T.TagName, ', ') AS Tags
FROM Posts P
LEFT JOIN Users U ON U.Id = P.OwnerUserId
LEFT JOIN Votes V ON V.PostId = P.Id
LEFT JOIN Posts A ON A.ParentId = P.Id AND A.PostTypeId = 2
LEFT JOIN PostLinks PL ON PL.PostId = P.Id AND PL.LinkTypeId = 3
LEFT JOIN Tags T ON P.Tags LIKE '%' || T.TagName || '%'
LEFT JOIN (
    SELECT B.UserId, SUM(CASE WHEN B.Class = 1 THEN 100 
                             WHEN B.Class = 2 THEN 50 
                             ELSE 10 END) AS ReputationChange
    FROM Badges B
    WHERE B.Date > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '2 year'
    GROUP BY B.UserId
) B ON B.UserId = U.Id
WHERE P.PostTypeId IN (1, 2)
  AND U.Reputation > 1000
  AND P.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 month'
GROUP BY U.DisplayName, U.Reputation, P.PostTypeId, P.Title
ORDER BY TotalVotes DESC, AvgReputationChange DESC
LIMIT 50;