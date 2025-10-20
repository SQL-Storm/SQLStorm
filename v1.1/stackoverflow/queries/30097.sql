-- {"query": "30097.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1962, "output_tokens": 28} 
SELECT PostId, COUNT(*) AS NumberOfVotes
FROM Votes
GROUP BY PostId
ORDER BY NumberOfVotes DESC;