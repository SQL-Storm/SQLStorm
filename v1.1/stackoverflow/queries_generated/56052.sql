-- {"query": "56052.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 453} 

WITH 
  top_users AS (
    SELECT 
      u.Id, 
      u.DisplayName, 
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes, 
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes
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
  top_tags AS (
    SELECT 
      t.TagName, 
      COUNT(*) AS count
    FROM 
      Posts p
    JOIN 
      Tags t ON p.Tags LIKE CONCAT('%', t.TagName, '%')
    GROUP BY 
      t.TagName
    HAVING 
      COUNT(*) > 1000
  ),
  user_tag_scores AS (
    SELECT 
      tu.Id, 
      tu.DisplayName, 
      tt.TagName, 
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS score
    FROM 
      top_users tu
    JOIN 
      Posts p ON tu.Id = p.OwnerUserId
    JOIN 
      Votes v ON p.Id = v.PostId
    JOIN 
      Tags t ON p.Tags LIKE CONCAT('%', t.TagName, '%')
    JOIN 
      top_tags tt ON t.TagName = tt.TagName
    WHERE 
      v.VoteTypeId = 2
    GROUP BY 
      tu.Id, tu.DisplayName, tt.TagName
  )
SELECT 
  uts.Id, 
  uts.DisplayName, 
  uts.TagName, 
  uts.score, 
  tu.upvotes, 
  tu.downvotes
FROM 
  user_tag_scores uts
JOIN 
  top_users tu ON uts.Id = tu.Id
ORDER BY 
  uts.score DESC;
