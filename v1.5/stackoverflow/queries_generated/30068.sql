-- {"query": "30068.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 66} 
SELECT P.Id, P.Title, P.ViewCount, COUNT(V.Id) AS VoteCount
FROM Posts P
LEFT JOIN Votes V ON P.Id = V.PostId
WHERE P.PostTypeId = 1
GROUP BY P.Id, P.Title, P.ViewCount
ORDER BY VoteCount DESC, P.ViewCount DESC;