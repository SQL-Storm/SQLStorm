WITH 
  top_users AS (
    SELECT Id, Reputation, DisplayName
    FROM Users
    ORDER BY Reputation DESC
    LIMIT 10
  ),
  popular_posts AS (
    SELECT Id, ViewCount, OwnerUserId, Title, PostTypeId, Tags
    FROM Posts
    WHERE ViewCount > 1000
  ),
  user_post_count AS (
    SELECT OwnerUserId, COUNT(*) AS post_count
    FROM Posts
    GROUP BY OwnerUserId
  ),
  avg_score_by_type AS (
    SELECT PostTypeId, AVG(Score) AS avg_score
    FROM Posts
    GROUP BY PostTypeId
  ),
  post_comment_count AS (
    SELECT PostId, COUNT(*) AS comment_count
    FROM Comments
    GROUP BY PostId
  ),
  post_vote_count AS (
    SELECT PostId, COUNT(*) AS vote_count
    FROM Votes
    GROUP BY PostId
  ),
  top_tags AS (
    SELECT TagName, Count
    FROM Tags
    ORDER BY Count DESC
    LIMIT 5
  ),
  post_tags_expanded AS (
    SELECT 
      p.Id,
      t.TagName
    FROM 
      popular_posts p,
      LATERAL (
        SELECT value AS TagName
        FROM unnest(string_to_array(substring(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><')) AS value
      ) t
  )
SELECT 
  pu.Id,
  pu.Reputation,
  pu.DisplayName,
  pp.ViewCount,
  pp.Title,
  upc.post_count,
  ascpt.avg_score,
  pcc.comment_count,
  pvc.vote_count,
  STRING_AGG(tt.TagName, ', ') AS top_tags
FROM 
  Users pu
  LEFT JOIN popular_posts pp ON pu.Id = pp.OwnerUserId
  LEFT JOIN user_post_count upc ON pu.Id = upc.OwnerUserId
  LEFT JOIN avg_score_by_type ascpt ON pp.PostTypeId = ascpt.PostTypeId
  LEFT JOIN post_comment_count pcc ON pp.Id = pcc.PostId
  LEFT JOIN post_vote_count pvc ON pp.Id = pvc.PostId
  LEFT JOIN post_tags_expanded pt ON pp.Id = pt.Id
  LEFT JOIN top_tags tt ON pt.TagName = tt.TagName
WHERE 
  pu.Id IN (SELECT Id FROM top_users)
GROUP BY 
  pu.Id,
  pu.Reputation,
  pu.DisplayName,
  pp.ViewCount,
  pp.Title,
  upc.post_count,
  ascpt.avg_score,
  pcc.comment_count,
  pvc.vote_count
ORDER BY 
  pu.Reputation DESC;