-- {"query": "26016.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 534} 

WITH 
  -- Calculate the total score for each user
  UserScores AS (
    SELECT 
      u.Id, 
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, 
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM 
      Users u
    LEFT JOIN 
      Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
      Votes v ON p.Id = v.PostId
    GROUP BY 
      u.Id
  ),
  
  -- Calculate the total badges for each user
  UserBadges AS (
    SELECT 
      u.Id, 
      COUNT(DISTINCT b.Name) AS TotalBadges
    FROM 
      Users u
    LEFT JOIN 
      Badges b ON u.Id = b.UserId
    GROUP BY 
      u.Id
  ),
  
  -- Calculate the average score for each post type
  PostTypeScores AS (
    SELECT 
      pt.Id, 
      AVG(p.Score) AS AverageScore
    FROM 
      PostTypes pt
    LEFT JOIN 
      Posts p ON pt.Id = p.PostTypeId
    GROUP BY 
      pt.Id
  ),
  
  -- Calculate the total comments for each post
  PostComments AS (
    SELECT 
      p.Id, 
      COUNT(c.Id) AS TotalComments
    FROM 
      Posts p
    LEFT JOIN 
      Comments c ON p.Id = c.PostId
    GROUP BY 
      p.Id
  )

SELECT 
  u.Id, 
  u.DisplayName, 
  u.Reputation, 
  us.UpVotes, 
  us.DownVotes, 
  ub.TotalBadges, 
  p.Id AS PostId, 
  p.Score, 
  p.ViewCount, 
  p.Title, 
  pc.TotalComments, 
  pts.AverageScore
FROM 
  Users u
LEFT JOIN 
  UserScores us ON u.Id = us.Id
LEFT JOIN 
  UserBadges ub ON u.Id = ub.Id
LEFT JOIN 
  Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
  PostComments pc ON p.Id = pc.Id
LEFT JOIN 
  PostTypeScores pts ON p.PostTypeId = pts.Id
WHERE 
  u.Reputation > 1000
  AND p.Score > 10
  AND pc.TotalComments > 5
  AND pts.AverageScore > 5
ORDER BY 
  u.Reputation DESC, 
  p.Score DESC;
