-- {"query": "14076.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 179795, "output_tokens": 76684} 
WITH cte AS (
  SELECT p.Id, p.PostTypeId, p.OwnerUserId, p.LastActivityDate, p.CreationDate, p.Title, p.Tags, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.Score, p.ViewCount,
         CASE WHEN p.PostTypeId = 1 THEN p.AcceptedAnswerId END AS AcceptedAnswerId,
         CASE WHEN p.PostTypeId = 2 THEN p.ParentId END AS ParentId,
         ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
)
SELECT c.Id, c.PostTypeId, c.OwnerUserId, c.LastActivityDate, c.CreationDate, c.Title, c.Tags, c.AnswerCount, c.CommentCount, c.FavoriteCount, c.Score, c.ViewCount,
       COALESCE(c.AcceptedAnswerId, (
         SELECT TOP 1 p.Id
         FROM Posts p
         WHERE p.ParentId = c.Id
         ORDER BY p.Score DESC, p.CreationDate ASC
       )) AS AcceptedAnswerId,
       (
         SELECT COUNT(*)
         FROM Votes v
         WHERE v.PostId = c.Id AND v.VoteTypeId IN (2, 3)
       ) AS VoteCount,
       (
         SELECT COUNT(*)
         FROM Comments cm
         WHERE cm.PostId = c.Id
       ) AS CommentCountTotal,
       (
         SELECT COUNT(*)
         FROM Badges b
         WHERE b.UserId = c.OwnerUserId
       ) AS BadgeCount,
       ROUND(c.Score * 1.0 / NULLIF(c.ViewCount, 0), 4) AS ScorePerView,
       CONCAT(SUBSTRING(c.Title, 1, 10), '...') AS TitlePreview,
       CASE WHEN c.rn = 1 THEN 'Most Recent' ELSE 'Other' END AS ActivityRank
FROM cte c
ORDER BY c.Score DESC, c.ViewCount DESC, c.CreationDate DESC;