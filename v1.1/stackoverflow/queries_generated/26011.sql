-- {"query": "26011.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 673} 

WITH 
  -- Get top 10 users by reputation
  top_users AS (
    SELECT Id, Reputation, DisplayName, 
    ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS row_num
    FROM Users
  ),
  
  -- Get posts with their respective scores and owners
  scored_posts AS (
    SELECT p.Id, p.Score, p.OwnerUserId, p.Title, 
    COALESCE(u.DisplayName, 'Unknown') AS owner_name
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
  ),
  
  -- Get post history for closed questions
  closed_post_history AS (
    SELECT ph.PostId, ph.Comment, 
    COALESCE(crt.Name, 'Unknown') AS close_reason
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON CAST(ph.Comment AS INT) = crt.Id
    WHERE ph.PostHistoryTypeId = 10
  ),
  
  -- Get post links for duplicates
  duplicate_links AS (
    SELECT pl.PostId, pl.RelatedPostId, 
    COALESCE(t.Name, 'Unknown') AS link_type
    FROM PostLinks pl
    LEFT JOIN LinkTypes t ON pl.LinkTypeId = t.Id
    WHERE pl.LinkTypeId = 3
  ),
  
  -- Get badges for users
  user_badges AS (
    SELECT b.UserId, b.Name, b.Date, 
    COALESCE(pt.Name, 'Unknown') AS post_type
    FROM Badges b
    LEFT JOIN Posts p ON b.UserId = p.OwnerUserId
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
  ),
  
  -- Get vote counts for posts
  post_votes AS (
    SELECT v.PostId, 
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS up_votes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS down_votes
    FROM Votes v
    GROUP BY v.PostId
  )

SELECT 
  tu.Id, tu.DisplayName, tu.Reputation, 
  COALESCE(sp.Score, 0) AS post_score, 
  COALESCE(cph.close_reason, 'Unknown') AS close_reason, 
  COALESCE(dl.RelatedPostId, 0) AS duplicate_id, 
  COALESCE(ub.Name, 'Unknown') AS badge_name, 
  COALESCE(pv.up_votes, 0) AS up_votes, 
  COALESCE(pv.down_votes, 0) AS down_votes
FROM top_users tu
LEFT JOIN scored_posts sp ON tu.Id = sp.OwnerUserId
LEFT JOIN closed_post_history cph ON sp.Id = cph.PostId
LEFT JOIN duplicate_links dl ON sp.Id = dl.PostId
LEFT JOIN user_badges ub ON tu.Id = ub.UserId
LEFT JOIN post_votes pv ON sp.Id = pv.PostId
WHERE tu.row_num <= 10
AND sp.Score > 0
AND cph.close_reason IS NOT NULL
AND dl.RelatedPostId IS NOT NULL
AND ub.Name IS NOT NULL
AND pv.up_votes > pv.down_votes
ORDER BY tu.Reputation DESC, sp.Score DESC;
