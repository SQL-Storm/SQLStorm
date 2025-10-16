-- {"query": "65.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 153} 
WITH complex_query AS (
    SELECT P.Id, P.Title, P.Score, P.CreationDate,
           U.DisplayName AS OwnerDisplayName, 
           SUM(V.Score) AS TotalVotes,
           COUNT(DISTINCT C.Id) AS TotalComments
    FROM Posts P
    LEFT JOIN Users U ON P.OwnerUserId = U.Id
    LEFT JOIN Votes V ON P.Id = V.PostId
    LEFT JOIN Comments C ON P.Id = C.PostId
    WHERE P.PostTypeId = 1
    GROUP BY P.Id, P.Title, P.Score, P.CreationDate, U.DisplayName
    HAVING COUNT(DISTINCT C.Id) > 5
    ORDER BY SUM(V.Score) DESC
)
SELECT * FROM complex_query;