-- {"query": "36083.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 408} 
SELECT
  p.Id AS PostId,
  p.Title,
  p.CreationDate,
  p.ViewCount,
  p.Score,
  p.Tags,
  p.OwnerDisplayName AS Owner,
  COALESCE(a.CountAnswers, 0) AS AnswerCount,
  COALESCE(vs.Upvotes, 0) AS Upvotes,
  COALESCE(vs.Downvotes, 0) AS Downvotes,
  COALESCE(b.CountBadges, 0) AS BadgeCount,
  COALESCE(cc.Comments, 0) AS CommentCount,
  p.LastEditDate,
  p.LastActivityDate,
  u.Reputation
FROM
  Posts p
  LEFT JOIN (
    SELECT ParentId, COUNT(*) AS CountAnswers
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY ParentId
  ) a ON a.ParentId = p.Id
  LEFT JOIN (
    SELECT PostId, SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS Upvotes,
           SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY PostId
  ) vs ON vs.PostId = p.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS CountBadges
    FROM Badges b
    GROUP BY PostId
  ) b ON b.PostId = p.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS Comments
    FROM Comments c
    GROUP BY PostId
  ) cc ON cc.PostId = p.Id
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
WHERE
  p.PostTypeId = 1
  AND p.AcceptedAnswerId IS NOT NULL
ORDER BY
  p.CreationDate DESC
LIMIT 100;