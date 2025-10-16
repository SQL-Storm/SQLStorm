-- {"query": "79.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 176} 
WITH CTE AS (
    SELECT P.Id AS PostId, P.Title, P.OwnerUserId, P.CreationDate,
           COUNT(V.Id) AS VoteCount, 
           ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate DESC) AS RowNum
    FROM Posts P
    LEFT JOIN Votes V ON P.Id = V.PostId
    WHERE P.PostTypeId = 1
    GROUP BY P.Id, P.Title, P.OwnerUserId, P.CreationDate
)
SELECT C.OwnerUserId, U.DisplayName AS OwnerDisplayName, 
       COUNT(DISTINCT L.Id) AS LinkCount
FROM CTE C
JOIN Users U ON C.OwnerUserId = U.Id
LEFT JOIN PostLinks L ON C.PostId = L.PostId
WHERE C.RowNum <= 10
GROUP BY C.OwnerUserId, U.DisplayName;