-- {"query": "26003.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 574} 

WITH TopContributors AS (
  SELECT 
    u.Id, 
    u.DisplayName, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, 
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes, 
    COUNT(DISTINCT p.Id) AS PostsCount
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
PostRanks AS (
  SELECT 
    p.Id, 
    p.Score, 
    ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS ScoreRank, 
    ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC) AS ViewCountRank
  FROM 
    Posts p
  WHERE 
    p.PostTypeId = 1
),
CommentsWithVotes AS (
  SELECT 
    c.Id, 
    c.PostId, 
    c.Score, 
    c.Text, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, 
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM 
    Comments c
  LEFT JOIN 
    Votes v ON c.Id = v.PostId AND v.VoteTypeId IN (2, 3)
  GROUP BY 
    c.Id, c.PostId, c.Score, c.Text
)
SELECT 
  p.Id, 
  p.Title, 
  p.Score, 
  p.ViewCount, 
  tc.UpVotes, 
  tc.DownVotes, 
  pr.ScoreRank, 
  pr.ViewCountRank, 
  cwv.Text AS TopCommentText, 
  cwv.UpVotes AS TopCommentUpVotes, 
  cwv.DownVotes AS TopCommentDownVotes
FROM 
  Posts p
JOIN 
  PostRanks pr ON p.Id = pr.Id
JOIN 
  TopContributors tc ON p.OwnerUserId = tc.Id
LEFT JOIN 
  CommentsWithVotes cwv ON p.Id = cwv.PostId AND cwv.Score = (SELECT MAX(Score) FROM CommentsWithVotes WHERE PostId = p.Id)
WHERE 
  p.PostTypeId = 1
  AND p.Score > 10
  AND p.ViewCount > 1000
  AND tc.UpVotes > 1000
ORDER BY 
  p.Score DESC, 
  p.ViewCount DESC;
