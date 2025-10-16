-- {"query": "14003.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 9340, "output_tokens": 4145} 

WITH cte_top_users AS (
  SELECT u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes, 
         RANK() OVER (ORDER BY u.Reputation DESC) AS reputation_rank
  FROM Users u
)
SELECT 
  p.Id AS post_id,
  p.Title,
  p.PostTypeId,
  p.CreationDate,
  p.OwnerUserId,
  ctu.DisplayName AS owner_display_name,
  ctu.Reputation AS owner_reputation,
  ctu.reputation_rank AS owner_reputation_rank,
  COALESCE(p.ParentId, p.Id) AS parent_id,
  CASE WHEN p.PostTypeId = 2 THEN 
    (SELECT COUNT(*) 
     FROM Comments c 
     WHERE c.PostId = p.Id)
  ELSE
    p.CommentCount
  END AS comment_count,
  CASE WHEN p.PostTypeId = 1 THEN 
    p.AnswerCount
  ELSE
    (SELECT COUNT(*)
     FROM Posts child_posts
     WHERE child_posts.ParentId = p.Id AND child_posts.PostTypeId = 2)
  END AS answer_count,
  CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 
    (SELECT p2.OwnerUserId
     FROM Posts p2
     WHERE p2.Id = p.AcceptedAnswerId)
  ELSE
    NULL
  END AS accepted_answer_owner_id,
  CASE WHEN p.PostTypeId = 1 THEN 
    p.FavoriteCount
  ELSE
    (SELECT COUNT(*)
     FROM Votes v
     WHERE v.PostId = p.Id AND v.VoteTypeId = 5)
  END AS favorite_count,
  CASE WHEN p.ClosedDate IS NOT NULL THEN
    (SELECT ct.Name
     FROM CloseReasonTypes ct
     JOIN PostHistory ph ON ph.Comment = CAST(ct.Id AS VARCHAR)
     WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
     ORDER BY ph.CreationDate DESC
     LIMIT 1)
  ELSE
    NULL
  END AS close_reason,
  CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN
    TRUE
  ELSE
    FALSE
  END AS is_community_owned,
  ROUND(CAST(DATEDIFF(SECOND, p.CreationDate, p.LastActivityDate) AS FLOAT) / 86400, 2) AS days_active,
  ROUND(CAST(DATEDIFF(SECOND, p.CreationDate, COALESCE(p.ClosedDate, CURRENT_TIMESTAMP)) AS FLOAT) / 86400, 2) AS days_open,
  CASE WHEN p.PostTypeId = 1 THEN
    STRING_AGG(DISTINCT t.TagName, '|')
  ELSE
    NULL
  END AS tags
FROM Posts p
LEFT JOIN cte_top_users ctu ON p.OwnerUserId = ctu.Id
LEFT JOIN Tags t ON STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><') @> ARRAY[t.TagName]
GROUP BY p.Id, p.Title, p.PostTypeId, p.CreationDate, p.OwnerUserId, ctu.DisplayName, ctu.Reputation, ctu.reputation_rank, p.ParentId, p.AcceptedAnswerId, p.CommentCount, p.AnswerCount, p.FavoriteCount, p.ClosedDate, p.CommunityOwnedDate, p.LastActivityDate
ORDER BY p.CreationDate DESC
LIMIT 100;
