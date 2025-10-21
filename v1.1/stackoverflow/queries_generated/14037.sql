-- {"query": "14037.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 683}
WITH CTE AS (
  SELECT p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.FavoriteCount, p.Title, p.Tags, p.OwnerUserId, u.Reputation, u.Views, u.UpVotes, u.DownVotes,
         CASE WHEN p.PostTypeId = 1 THEN p.AcceptedAnswerId ELSE NULL END AS AcceptedAnswerId,
         CASE WHEN p.PostTypeId = 2 THEN p.ParentId ELSE NULL END AS ParentId,
         DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS OwnerPostRank,
         RANK() OVER (PARTITION BY p.Tags ORDER BY p.Score DESC) AS TagRank
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
),
Interactions AS (
  SELECT c.PostId, COUNT(*) AS CommentCount
  FROM Comments c
  GROUP BY c.PostId
),
Votes AS (
  SELECT v.PostId, COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
                 COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
                 COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS Favorites
  FROM Votes v
  GROUP BY v.PostId
)
SELECT c.Id, c.PostTypeId, c.CreationDate, c.Score, c.ViewCount, c.AnswerCount, c.FavoriteCount, c.Title, c.Tags, c.OwnerUserId, c.Reputation, c.Views, c.UpVotes, c.DownVotes,
       CASE WHEN c.PostTypeId = 1 THEN c.AcceptedAnswerId ELSE NULL END AS AcceptedAnswerId,
       CASE WHEN c.PostTypeId = 2 THEN c.ParentId ELSE NULL END AS ParentId,
       c.OwnerPostRank, c.TagRank,
       i.CommentCount,
       v.UpVotes AS VoteUpCount,
       v.DownVotes AS VoteDownCount,
       v.Favorites AS FavoriteCount
FROM CTE c
LEFT JOIN Interactions i ON c.Id = i.PostId
LEFT JOIN Votes v ON c.Id = v.PostId
WHERE c.OwnerPostRank <= 5 AND c.TagRank <= 3
ORDER BY c.Score DESC, c.ViewCount DESC
LIMIT 100;
