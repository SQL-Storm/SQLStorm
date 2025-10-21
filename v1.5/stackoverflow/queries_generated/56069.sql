-- {"query": "56069.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 338} 

WITH TopPosts AS (
  SELECT p.Id, p.Score, p.ViewCount, p.Title, p.Tags, p.AcceptedAnswerId,
         ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS RowNum
  FROM Posts p
  WHERE p.PostTypeId = 1 AND p.Score > 100
),
TopUsers AS (
  SELECT u.Id, u.DisplayName, u.Reputation,
         ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RowNum
  FROM Users u
  WHERE u.Reputation > 10000
),
PostVotes AS (
  SELECT p.Id, COUNT(v.Id) AS VoteCount
  FROM Posts p
  JOIN Votes v ON p.Id = v.PostId
  WHERE v.VoteTypeId = 2
  GROUP BY p.Id
),
PostAnswers AS (
  SELECT p.Id, COUNT(a.Id) AS AnswerCount
  FROM Posts p
  JOIN Posts a ON p.Id = a.ParentId
  WHERE a.PostTypeId = 2
  GROUP BY p.Id
)
SELECT 
  p.Id, 
  p.Score, 
  p.ViewCount, 
  p.Title, 
  p.Tags, 
  p.AcceptedAnswerId, 
  u.DisplayName AS TopUser, 
  pv.VoteCount, 
  pa.AnswerCount
FROM TopPosts p
JOIN TopUsers u ON p.OwnerUserId = u.Id
JOIN PostVotes pv ON p.Id = pv.Id
JOIN PostAnswers pa ON p.Id = pa.Id
WHERE p.RowNum <= 10 AND u.RowNum <= 10
ORDER BY p.Score DESC;
