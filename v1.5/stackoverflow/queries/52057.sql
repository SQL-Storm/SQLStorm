-- {"query": "52057.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 442} 
SELECT p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount,
       u.DisplayName as Owner, u.Reputation,
       COALESCE(ph.edit_count, 0) as EditCount,
       COALESCE(vh.upvote_count, 0) as UpvoteCount,
       COALESCE(vh.downvote_count, 0) as DownvoteCount,
       COALESCE(vh.fav_count, 0) as FavoriteCount,
       array_length(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), 1) as TagCount,
       COALESCE(pl.link_count, 0) as LinkedPostCount,
       ROW_NUMBER() OVER (ORDER BY COALESCE(ph.edit_count, 0) DESC, p.Score DESC) as RankByEditsAndScore
FROM Posts p
JOIN Users u ON u.Id = p.OwnerUserId
LEFT JOIN (
  SELECT PostId, COUNT(*) as edit_count
  FROM PostHistory
  WHERE PostHistoryTypeId IN (4,5,6,7,8,9,24)  -- edits and applied edits
  GROUP BY PostId
) ph ON ph.PostId = p.Id
LEFT JOIN (
  SELECT PostId,
         SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) as upvote_count,
         SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) as downvote_count,
         SUM(CASE WHEN VoteTypeId = 5 THEN 1 ELSE 0 END) as fav_count
  FROM Votes
  GROUP BY PostId
) vh ON vh.PostId = p.Id
LEFT JOIN (
  SELECT PostId, COUNT(*) as link_count
  FROM PostLinks
  GROUP BY PostId
) pl ON pl.PostId = p.Id
WHERE p.PostTypeId = 1
  AND p.CreationDate >= '2008-01-01'
  AND u.Reputation > 100
ORDER BY COALESCE(ph.edit_count, 0) DESC, p.Score DESC
LIMIT 500;