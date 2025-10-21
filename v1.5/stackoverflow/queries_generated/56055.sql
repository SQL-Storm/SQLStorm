-- {"query": "56055.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "llama-3.3-instruct", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 475} 

WITH 
  top_posts AS (
    SELECT 
      p.Id, 
      p.Score, 
      p.ViewCount, 
      p.AnswerCount, 
      p.CommentCount, 
      p.FavoriteCount, 
      u.Reputation AS OwnerReputation
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
  top_post_votes AS (
    SELECT 
      p.Id, 
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes, 
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM 
      top_posts p
    JOIN 
      Votes v ON p.Id = v.PostId
    GROUP BY 
      p.Id
  ),
  top_post_badges AS (
    SELECT 
      p.Id, 
      COUNT(DISTINCT b.Name) AS BadgeCount
    FROM 
      top_posts p
    JOIN 
      Users u ON p.OwnerUserId = u.Id
    JOIN 
      Badges b ON u.Id = b.UserId
    GROUP BY 
      p.Id
  ),
  top_post_history AS (
    SELECT 
      p.Id, 
      COUNT(DISTINCT ph.PostHistoryTypeId) AS HistoryCount
    FROM 
      top_posts p
    JOIN 
      PostHistory ph ON p.Id = ph.PostId
    GROUP BY 
      p.Id
  )
SELECT 
  tp.Id, 
  tp.Score, 
  tp.ViewCount, 
  tp.AnswerCount, 
  tp.CommentCount, 
  tp.FavoriteCount, 
  tp.OwnerReputation, 
  tpv.UpVotes, 
  tpv.DownVotes, 
  tpb.BadgeCount, 
  tph.HistoryCount
FROM 
  top_posts tp
JOIN 
  top_post_votes tpv ON tp.Id = tpv.Id
JOIN 
  top_post_badges tpb ON tp.Id = tpb.Id
JOIN 
  top_post_history tph ON tp.Id = tph.Id
ORDER BY 
  tp.Score DESC;
