-- {"query": "30030.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 65} 
SELECT DISTINCT P1.Id, P1.Title, P1.ViewCount, P1.Score, P1.Tags, P1.CreationDate
FROM Posts P1
JOIN Votes V ON P1.Id = V.PostId
JOIN Users U ON V.UserId = U.Id
WHERE U.Reputation > 100000;