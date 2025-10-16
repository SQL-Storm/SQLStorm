-- {"query": "26072.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 492} 

WITH TopUsers AS (
  SELECT 
    u.Id, 
    u.DisplayName, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, 
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId
  LEFT JOIN Votes v ON p.Id = v.PostId
  GROUP BY u.Id, u.DisplayName
  HAVING SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 1000
),
TopTags AS (
  SELECT 
    t.TagName, 
    COUNT(p.Id) AS PostCount
  FROM Tags t
  LEFT JOIN Posts p ON t.Id = (SELECT Id FROM Tags WHERE TagName = ANY(string_to_array(p.Tags, '<')))
  GROUP BY t.TagName
  HAVING COUNT(p.Id) > 100
),
QuestionAnswers AS (
  SELECT 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount
  FROM Posts p
  WHERE p.PostTypeId = 1
),
AnswerPosts AS (
  SELECT 
    p.Id, 
    p.Score, 
    p.ParentId, 
    (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 9) AS BountyAmount
  FROM Posts p
  WHERE p.PostTypeId = 2
)
SELECT 
  tu.DisplayName, 
  tt.TagName, 
  qa.Title, 
  qa.Score, 
  qa.ViewCount, 
  qa.AnswerCount, 
  qa.CommentCount, 
  ap.Score AS AnswerScore, 
  ap.BountyAmount
FROM TopUsers tu
JOIN QuestionAnswers qa ON tu.Id = qa.Id
JOIN TopTags tt ON qa.Id = (SELECT p.Id FROM Posts p WHERE p.Tags LIKE '%' + tt.TagName + '%')
JOIN AnswerPosts ap ON qa.Id = ap.ParentId
WHERE ap.BountyAmount > 100
ORDER BY tu.UpVotes DESC, qa.Score DESC, ap.Score DESC
LIMIT 100;
