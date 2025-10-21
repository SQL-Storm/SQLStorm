-- {"query": "56035.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 464} 
WITH TopUsers AS (
  SELECT 
    u.Id, 
    u.DisplayName, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, 
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM 
    Users u
  JOIN 
    Posts p ON u.Id = p.OwnerUserId
  JOIN 
    Votes v ON p.Id = v.PostId
  WHERE 
    v.VoteTypeId IN (2, 3)
  GROUP BY 
    u.Id, u.DisplayName
  HAVING 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 1000
),
TopTags AS (
  SELECT 
    t.TagName, 
    COUNT(p.Id) AS PostCount
  FROM 
    Posts p
  JOIN 
    Tags t ON p.Tags LIKE CONCAT('%', t.TagName, '%')
  GROUP BY 
    t.TagName
  HAVING 
    COUNT(p.Id) > 1000
),
QuestionAnswers AS (
  SELECT 
    p.Id, 
    p.Score, 
    COUNT(a.Id) AS AnswerCount
  FROM 
    Posts p
  LEFT JOIN 
    Posts a ON p.Id = a.ParentId
  WHERE 
    p.PostTypeId = 1
  GROUP BY 
    p.Id, p.Score
)
SELECT 
  u.DisplayName, 
  tu.UpVotes, 
  tu.DownVotes, 
  tt.TagName, 
  qa.Score, 
  qa.AnswerCount
FROM 
  TopUsers tu
JOIN 
  Users u ON tu.Id = u.Id
JOIN 
  Posts p ON u.Id = p.OwnerUserId
JOIN 
  QuestionAnswers qa ON p.Id = qa.Id
JOIN 
  Tags t ON p.Tags LIKE CONCAT('%', t.TagName, '%')
JOIN 
  TopTags tt ON t.TagName = tt.TagName
WHERE 
  p.PostTypeId = 1
  AND p.Score > 10
  AND qa.AnswerCount > 5
ORDER BY 
  tu.UpVotes DESC, 
  tu.DownVotes ASC;