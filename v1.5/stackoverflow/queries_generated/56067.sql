-- {"query": "56067.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 461} 

WITH TopPosts AS (
  SELECT 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.AnswerCount, 
    p.CommentCount, 
    p.FavoriteCount, 
    ROW_NUMBER() OVER (ORDER BY p.Score DESC) AS ScoreRank,
    ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC) AS ViewRank
  FROM 
    Posts p
  WHERE 
    p.PostTypeId = 1 AND p.ClosedDate IS NULL
),
TopUsers AS (
  SELECT 
    u.Id, 
    u.DisplayName, 
    u.Reputation, 
    COUNT(DISTINCT p.Id) AS PostCount,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
  FROM 
    Users u
  JOIN 
    Posts p ON u.Id = p.OwnerUserId
  WHERE 
    p.PostTypeId = 1 AND p.ClosedDate IS NULL
  GROUP BY 
    u.Id, u.DisplayName, u.Reputation
),
TopTags AS (
  SELECT 
    t.TagName, 
    COUNT(DISTINCT p.Id) AS PostCount,
    ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) AS TagRank
  FROM 
    Posts p
  JOIN 
    Tags t ON p.Tags LIKE CONCAT('%', t.TagName, '%')
  WHERE 
    p.PostTypeId = 1 AND p.ClosedDate IS NULL
  GROUP BY 
    t.TagName
)
SELECT 
  tp.Id, 
  tp.Title, 
  tp.Score, 
  tp.ViewCount, 
  tp.AnswerCount, 
  tp.CommentCount, 
  tp.FavoriteCount, 
  tu.DisplayName AS TopUserDisplayName, 
  tu.Reputation AS TopUserReputation, 
  tt.TagName AS TopTag
FROM 
  TopPosts tp
JOIN 
  TopUsers tu ON tp.OwnerUserId = tu.Id
JOIN 
  TopTags tt ON tp.Tags LIKE CONCAT('%', tt.TagName, '%')
WHERE 
  tp.ScoreRank <= 10 AND tu.ReputationRank <= 10 AND tt.TagRank <= 10
ORDER BY 
  tp.Score DESC;
