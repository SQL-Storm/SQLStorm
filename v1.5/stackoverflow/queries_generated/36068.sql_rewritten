-- {"query": "36068.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 441} 
SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  p.CreationDate,
  p.ViewCount,
  p.Score,
  p.OwnerUserId,
  p.OwnerDisplayName,
  p.Tags,
  p.AnswerCount,
  p.CommentCount,
  p.FavoriteCount,
  pv.TotalUpVotes,
  pv.TotalDownVotes,
  pc.TotalCommentsByUsers,
  phh.RevisionCount,
  COALESCE(blb.BadgeCount, 0) AS BadgeCount,
  u.Reputation,
  u.CreationDate AS UserCreationDate,
  u.LastAccessDate,
  u.Location,
  u.WebsiteUrl,
  u.ProfileImageUrl
FROM
  Posts p
  LEFT JOIN (
    SELECT
      PostId,
      SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
      SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS TotalDownVotes
    FROM Votes v
      INNER JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY PostId
  ) pv ON p.Id = pv.PostId
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS TotalCommentsByUsers
    FROM Comments
    GROUP BY PostId
  ) pc ON p.Id = pc.PostId
  LEFT JOIN (
    SELECT PostHistory.PostId, COUNT(*) AS RevisionCount
    FROM PostHistory
    GROUP BY PostHistory.PostId
  ) phh ON p.Id = phh.PostId
  LEFT JOIN (
    SELECT OwnerUserId, COUNT(*) AS BadgeCount
    FROM Badges
    GROUP BY OwnerUserId
  ) blb ON p.OwnerUserId = blb.OwnerUserId
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
WHERE
  p.PostTypeId IN (1, 2)
  AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
ORDER BY
  p.CreationDate DESC
LIMIT 100;