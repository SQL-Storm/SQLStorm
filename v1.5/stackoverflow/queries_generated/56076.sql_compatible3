WITH 
  top_posts AS (
    SELECT 
      p.Id, 
      p.Score, 
      p.ViewCount, 
      p.Title, 
      p.Tags, 
      p.OwnerUserId, 
      u.Reputation, 
      u.DisplayName
    FROM 
      Posts p 
    JOIN 
      Users u ON p.OwnerUserId = u.Id 
    WHERE 
      p.PostTypeId = 1 
    ORDER BY 
      p.Score DESC 
    LIMIT 100
  ),
  top_post_tags AS (
    SELECT 
      p.Id, 
      string_to_array(substr(p.Tags, 2, length(p.Tags) - 2), '<>') AS tags
    FROM 
      Posts p 
    WHERE 
      p.Id IN (SELECT Id FROM top_posts)
  ),
  top_tag_count AS (
    SELECT 
      unnest(tags) AS tag, 
      COUNT(*) AS count 
    FROM 
      top_post_tags 
    GROUP BY 
      unnest(tags) 
    ORDER BY 
      count DESC 
    LIMIT 10
  ),
  top_tag_posts AS (
    SELECT 
      p.Id, 
      p.Score, 
      p.ViewCount, 
      p.Title, 
      p.Tags, 
      p.OwnerUserId, 
      u.Reputation, 
      u.DisplayName 
    FROM 
      Posts p 
    JOIN 
      Users u ON p.OwnerUserId = u.Id 
    WHERE 
      p.Id IN (SELECT Id FROM top_posts) 
      AND (
        EXISTS (
          SELECT 1
          FROM top_tag_count ttc
          WHERE p.Tags LIKE '%' || '<' || ttc.tag || '>' || '%'
        )
      )
  )
SELECT 
  ttp.Id, 
  ttp.Score, 
  ttp.ViewCount, 
  ttp.Title, 
  ttp.Tags, 
  ttp.OwnerUserId, 
  ttp.Reputation, 
  ttp.DisplayName, 
  COUNT(DISTINCT v.Id) AS vote_count, 
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvote_count, 
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvote_count 
FROM 
  top_tag_posts ttp 
LEFT JOIN 
  Votes v ON ttp.Id = v.PostId 
GROUP BY 
  ttp.Id, 
  ttp.Score, 
  ttp.ViewCount, 
  ttp.Title, 
  ttp.Tags, 
  ttp.OwnerUserId, 
  ttp.Reputation, 
  ttp.DisplayName 
ORDER BY 
  vote_count DESC;