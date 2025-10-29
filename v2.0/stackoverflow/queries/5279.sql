-- {"query": "5279.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 674} 
SELECT
  u.DisplayName AS UserName,
  u.Id AS UserId,
  u.Reputation,
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  p.CreationDate,
  p.LastActivityDate,
  pv.TotalUpvotes,
  pv.TotalDownvotes,
  COALESCE(pc.CommentCount, 0) AS CommentCountOnPost,
  COALESCE(pl.TotalLinks, 0) AS LinkedPostsCount,
  v_vt.VoteCount AS RecentUpvoteCount,
  u2.DisplayName AS LastEditorName,
  u2.Id AS LastEditorId,
  b.BadgeGoldCount,
  b.BadgeSilverCount,
  b.BadgeBronzeCount
FROM
  Posts p
JOIN
  Users u ON p.OwnerUserId = u.Id
LEFT JOIN
  ( -- aggregate post votes
    SELECT
      PostId,
      SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
      SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS TotalDownvotes
    FROM
      Votes v
    JOIN
      VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY
      PostId
  ) pv ON pv.PostId = p.Id
LEFT JOIN
  Comments c ON c.PostId = p.Id
LEFT JOIN
  (SELECT PostId, COUNT(*) AS CommentCount FROM Comments GROUP BY PostId) pc ON pc.PostId = p.Id
LEFT JOIN
  (SELECT PostId, COUNT(*) AS TotalLinks FROM PostLinks GROUP BY PostId) pl ON pl.PostId = p.Id
LEFT JOIN
  ( -- recent upvotes for the post
    SELECT
      PostId,
      COUNT(*) AS VoteCount
    FROM
      Votes v
    JOIN
      VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE
      vt.Id = 2 -- UpMod
      AND v.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '7 days'
    GROUP BY
      PostId
  ) v_vt ON v_vt.PostId = p.Id
LEFT JOIN
  Posts p2 ON p.LastEditorUserId = p2.OwnerUserId AND p.LastEditorDisplayName = p2.OwnerDisplayName
LEFT JOIN
  Users u2 ON p.LastEditorUserId = u2.Id
LEFT JOIN
  ( -- badge counts by user
    SELECT
      UserId,
      SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS BadgeGoldCount,
      SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS BadgeSilverCount,
      SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BadgeBronzeCount
    FROM
      Badges
    GROUP BY
      UserId
  ) b ON b.UserId = u.Id
WHERE
  p.PostTypeId IN (1, 2) -- questions and answers
  AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '180 days'
ORDER BY
  p.CreationDate DESC
LIMIT 100;