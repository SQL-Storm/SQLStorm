-- {"query": "26040.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 479} 

WITH TopUsers AS (
  SELECT 
    u.Id, 
    u.DisplayName, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, 
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Users u
  JOIN Posts p ON u.Id = p.OwnerUserId
  JOIN Votes v ON p.Id = v.PostId
  GROUP BY u.Id, u.DisplayName
  HAVING SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 1000
),
TopTags AS (
  SELECT 
    t.TagName, 
    COUNT(p.Id) AS PostCount
  FROM Tags t
  JOIN Posts p ON t.Id = (SELECT Id FROM Tags WHERE TagName = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), ''><'')))
  GROUP BY t.TagName
  HAVING COUNT(p.Id) > 1000
),
PostScores AS (
  SELECT 
    p.Id, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    p.CommentCount, 
    ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS RowNum
  FROM Posts p
  JOIN TopUsers tu ON p.OwnerUserId = tu.Id
  JOIN TopTags tt ON tt.TagName = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), ''><''))
)
SELECT 
  p.Id, 
  p.Title, 
  p.Score, 
  p.ViewCount, 
  p.AnswerCount, 
  p.CommentCount, 
  tu.DisplayName AS TopUser, 
  tt.TagName AS TopTag, 
  ps.RowNum AS ScoreRank
FROM Posts p
JOIN PostScores ps ON p.Id = ps.Id
JOIN TopUsers tu ON p.OwnerUserId = tu.Id
JOIN TopTags tt ON tt.TagName = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), ''><''))
WHERE p.Score > 100 AND p.ViewCount > 10000 AND ps.RowNum < 100
ORDER BY p.Score DESC, p.ViewCount DESC;
