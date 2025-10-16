-- {"query": "26049.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 522} 

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
    u.Id, u.DisplayName
  HAVING 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 1000
),
QuestionPosts AS (
  SELECT 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    p.CommentCount, 
    p.ClosedDate
  FROM 
    Posts p
  WHERE 
    p.PostTypeId = 1
),
AnswerPosts AS (
  SELECT 
    p.Id, 
    p.ParentId, 
    p.Score, 
    p.CommentCount
  FROM 
    Posts p
  WHERE 
    p.PostTypeId = 2
),
TopQuestions AS (
  SELECT 
    q.Id, 
    q.Title, 
    q.Score, 
    q.ViewCount, 
    q.AnswerCount, 
    q.CommentCount, 
    q.ClosedDate, 
    ROW_NUMBER() OVER (ORDER BY q.Score DESC) AS RowNum
  FROM 
    QuestionPosts q
)
SELECT 
  tu.DisplayName, 
  tu.UpVotes, 
  tu.DownVotes, 
  q.Title, 
  q.Score, 
  q.ViewCount, 
  q.AnswerCount, 
  q.CommentCount, 
  q.ClosedDate, 
  a.Score AS AnswerScore, 
  a.CommentCount AS AnswerCommentCount, 
  ph.Comment AS PostHistoryComment
FROM 
  TopUsers tu
LEFT JOIN 
  Posts p ON tu.Id = p.OwnerUserId
LEFT JOIN 
  TopQuestions q ON p.Id = q.Id
LEFT JOIN 
  AnswerPosts a ON p.Id = a.ParentId
LEFT JOIN 
  PostHistory ph ON p.Id = ph.PostId
WHERE 
  q.RowNum <= 10
  AND ph.PostHistoryTypeId = 10
  AND ph.Comment IS NOT NULL
ORDER BY 
  tu.UpVotes DESC, 
  q.Score DESC;
