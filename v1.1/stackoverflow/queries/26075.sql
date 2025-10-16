WITH RankedPosts AS (
  SELECT 
    p.Id, 
    p.Score, 
    p.ViewCount, 
    p.Title, 
    p.Tags, 
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS RowNum,
    LAG(p.Score, 1) OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS PrevScore,
    LEAD(p.Score, 1) OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS NextScore,
    p.PostTypeId,
    p.ParentId
  FROM 
    Posts p
  WHERE 
    p.PostTypeId IN (1, 2)
),
UserReputation AS (
  SELECT 
    u.Id, 
    u.Reputation, 
    u.CreationDate, 
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRowNum
  FROM 
    Users u
),
QuestionAnswers AS (
  SELECT 
    p.Id, 
    p.ParentId, 
    p.Score, 
    p.ViewCount, 
    p.Title, 
    p.Tags, 
    COUNT(DISTINCT c.Id) AS CommentCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM 
    Posts p
  LEFT JOIN 
    Comments c ON p.Id = c.PostId
  LEFT JOIN 
    Votes v ON p.Id = v.PostId
  WHERE 
    p.PostTypeId = 1
  GROUP BY 
    p.Id, p.ParentId, p.Score, p.ViewCount, p.Title, p.Tags
),
AnswerDetails AS (
  SELECT 
    p.Id, 
    p.ParentId, 
    p.Score, 
    p.ViewCount, 
    p.Title, 
    p.Tags, 
    COUNT(DISTINCT c.Id) AS CommentCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
  FROM 
    Posts p
  LEFT JOIN 
    Comments c ON p.Id = c.PostId
  LEFT JOIN 
    Votes v ON p.Id = v.PostId
  WHERE 
    p.PostTypeId = 2
  GROUP BY 
    p.Id, p.ParentId, p.Score, p.ViewCount, p.Title, p.Tags
)
SELECT 
  rp.Id, 
  rp.Score, 
  rp.ViewCount, 
  rp.Title, 
  rp.Tags, 
  ur.Reputation, 
  ur.CreationDate, 
  q.Title AS QuestionTitle, 
  q.Tags AS QuestionTags, 
  a.Title AS AnswerTitle, 
  a.Tags AS AnswerTags,
  CASE 
    WHEN rp.Score > 0 THEN 'Positive'
    WHEN rp.Score < 0 THEN 'Negative'
    ELSE 'Neutral'
  END AS ScoreType,
  CASE 
    WHEN ur.Reputation > 1000 THEN 'High'
    WHEN ur.Reputation > 100 THEN 'Medium'
    ELSE 'Low'
  END AS ReputationType,
  ROW_NUMBER() OVER (ORDER BY rp.Score DESC) AS FinalRowNum
FROM 
  RankedPosts rp
LEFT JOIN 
  UserReputation ur ON rp.Id = ur.Id
LEFT JOIN 
  QuestionAnswers q ON rp.ParentId = q.ParentId OR rp.ParentId = q.Id
LEFT JOIN 
  AnswerDetails a ON rp.Id = a.Id
WHERE 
  rp.RowNum <= 10
  AND ur.RepRowNum <= 10
  AND q.CommentCount > 0
  AND a.CommentCount > 0
  AND rp.Score > 0
  AND ur.Reputation > 0
ORDER BY 
  rp.Score DESC;