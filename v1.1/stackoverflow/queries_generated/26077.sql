-- {"query": "26077.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 637} 

WITH 
  -- Calculate the average reputation of users who have asked at least one question
  avg_reputation AS (
    SELECT AVG(u.Reputation) AS avg_rep
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
  ),
  
  -- Get the top 10 tags with the most questions
  top_tags AS (
    SELECT t.TagName, COUNT(*) AS question_count
    FROM Tags t
    JOIN Posts p ON t.Id = (
      SELECT Id
      FROM Tags
      WHERE TagName = ANY(string_to_array(p.Tags, '><'))
    )
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName
    ORDER BY question_count DESC
    LIMIT 10
  ),
  
  -- Calculate the number of upvotes and downvotes for each post
  post_votes AS (
    SELECT p.Id, 
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes
    FROM Posts p
    JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.Id
  ),
  
  -- Get the posts with the most upvotes and downvotes
  top_posts AS (
    SELECT p.Id, p.Title, pv.upvotes, pv.downvotes
    FROM Posts p
    JOIN post_votes pv ON p.Id = pv.Id
    ORDER BY pv.upvotes DESC, pv.downvotes DESC
    LIMIT 10
  ),
  
  -- Calculate the average score of posts for each user
  user_avg_score AS (
    SELECT u.Id, AVG(p.Score) AS avg_score
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id
  )

SELECT 
  u.Id, 
  u.DisplayName, 
  u.Reputation, 
  uas.avg_score, 
  COALESCE(tp.Title, 'No top post') AS top_post_title,
  COALESCE(tp.upvotes, 0) AS top_post_upvotes,
  COALESCE(tp.downvotes, 0) AS top_post_downvotes,
  COALESCE(tt.TagName, 'No top tag') AS top_tag,
  ar.avg_rep AS avg_reputation
FROM Users u
LEFT JOIN user_avg_score uas ON u.Id = uas.Id
LEFT JOIN top_posts tp ON u.Id = tp.Id
LEFT JOIN top_tags tt ON u.Id = (
  SELECT u.Id
  FROM Users u
  JOIN Posts p ON u.Id = p.OwnerUserId
  JOIN Tags t ON t.Id = (
    SELECT Id
    FROM Tags
    WHERE TagName = ANY(string_to_array(p.Tags, '><'))
  )
  WHERE t.TagName = tt.TagName
)
CROSS JOIN avg_reputation ar
WHERE u.Reputation > (SELECT avg_rep FROM avg_reputation)
ORDER BY u.Reputation DESC;
