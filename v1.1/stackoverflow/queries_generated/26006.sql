-- {"query": "26006.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 646} 

WITH TopUsers AS (
  SELECT 
    u.Id, 
    u.DisplayName, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, 
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM 
    Users u
  LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
  LEFT JOIN 
    Votes v ON p.Id = v.PostId
  GROUP BY 
    u.Id, 
    u.DisplayName
),
TopPosts AS (
  SELECT 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS ScoreRank,
    ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC) AS ViewCountRank
  FROM 
    Posts p
),
QuestionAnswers AS (
  SELECT 
    p.Id AS QuestionId, 
    p.Title AS QuestionTitle, 
    a.Id AS AnswerId, 
    a.Score AS AnswerScore
  FROM 
    Posts p
  LEFT JOIN 
    Posts a ON p.Id = a.ParentId
  WHERE 
    p.PostTypeId = 1 AND a.PostTypeId = 2
),
AnswerCounts AS (
  SELECT 
    p.Id, 
    COUNT(a.Id) AS AnswerCount
  FROM 
    Posts p
  LEFT JOIN 
    Posts a ON p.Id = a.ParentId
  WHERE 
    p.PostTypeId = 1 AND a.PostTypeId = 2
  GROUP BY 
    p.Id
)
SELECT 
  p.Id, 
  p.Title, 
  p.Score, 
  p.ViewCount, 
  COALESCE(qa.AnswerId, 0) AS AnswerId, 
  COALESCE(qa.AnswerScore, 0) AS AnswerScore, 
  COALESCE(ac.AnswerCount, 0) AS AnswerCount,
  tu.UpVotes, 
  tu.DownVotes, 
  CASE 
    WHEN p.Score > 100 THEN 'Highly Scored'
    WHEN p.Score > 50 THEN 'Moderately Scored'
    ELSE 'Lowly Scored'
  END AS ScoreCategory,
  CASE 
    WHEN p.ViewCount > 1000 THEN 'Highly Viewed'
    WHEN p.ViewCount > 500 THEN 'Moderately Viewed'
    ELSE 'Lowly Viewed'
  END AS ViewCountCategory,
  tp.ScoreRank, 
  tp.ViewCountRank,
  p.Tags, 
  p.Body
FROM 
  Posts p
LEFT JOIN 
  QuestionAnswers qa ON p.Id = qa.QuestionId
LEFT JOIN 
  AnswerCounts ac ON p.Id = ac.Id
LEFT JOIN 
  TopUsers tu ON p.OwnerUserId = tu.Id
LEFT JOIN 
  TopPosts tp ON p.Id = tp.Id
WHERE 
  p.PostTypeId = 1 AND p.Score > 0 AND p.ViewCount > 0
ORDER BY 
  p.Score DESC, 
  p.ViewCount DESC;
