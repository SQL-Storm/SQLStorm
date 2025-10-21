-- {"query": "30063.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 53} 
SELECT P.Id, P.Title, P.Score, P.CreationDate, U.DisplayName
FROM Posts P
JOIN Users U ON P.OwnerUserId = U.Id
WHERE P.PostTypeId = 1
ORDER BY P.Score DESC, P.CreationDate DESC;