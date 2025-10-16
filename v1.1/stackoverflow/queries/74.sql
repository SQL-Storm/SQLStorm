-- {"query": "74.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 306} 
WITH cte1 AS (
    SELECT P.Id, P.Title, P.Score, P.CreationDate, U.DisplayName AS OwnerDisplayName
    FROM Posts P
    JOIN Users U ON P.OwnerUserId = U.Id
    WHERE P.PostTypeId = 1
), cte2 AS (
    SELECT P.Id, COUNT(*) AS AnswerCount
    FROM Posts P
    WHERE P.PostTypeId = 1
    AND P.ParentId IS NULL
    GROUP BY P.Id
), cte3 AS (
    SELECT P.Id, COUNT(*) AS VoteCount
    FROM Posts P
    LEFT JOIN Votes V ON P.Id = V.PostId
    WHERE V.VoteTypeId = 2
    GROUP BY P.Id
), cte4 AS (
    SELECT P.Id, COUNT(*) AS CommentCount
    FROM Posts P
    LEFT JOIN Comments C ON P.Id = C.PostId
    GROUP BY P.Id
)
SELECT cte1.Id, cte1.Title, cte1.Score, cte1.CreationDate, cte1.OwnerDisplayName, 
       cte2.AnswerCount, cte3.VoteCount, cte4.CommentCount
FROM cte1
LEFT JOIN cte2 ON cte1.Id = cte2.Id
LEFT JOIN cte3 ON cte1.Id = cte3.Id
LEFT JOIN cte4 ON cte1.Id = cte4.Id
ORDER BY cte1.CreationDate DESC;