-- {"query": "91.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 172} 
WITH UserActivity AS (
    SELECT 
        U.Id,
        U.DisplayName,
        COUNT(DISTINCT P.Id) AS NumPosts,
        SUM(V.Score) AS TotalVotes
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Votes V ON P.Id = V.PostId
    GROUP BY U.Id, U.DisplayName
)

SELECT 
    UA.Id,
    UA.DisplayName,
    UA.NumPosts,
    UA.TotalVotes,
    CASE
        WHEN UA.NumPosts >= 10 AND UA.TotalVotes >= 100 THEN 'Active User'
        WHEN UA.NumPosts >= 5 AND UA.TotalVotes >= 50 THEN 'Moderately Active User'
        ELSE 'Inactive User'
    END AS UserStatus
FROM UserActivity UA
ORDER BY UA.TotalVotes DESC, UA.NumPosts DESC;