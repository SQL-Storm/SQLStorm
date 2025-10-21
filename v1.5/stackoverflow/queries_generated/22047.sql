-- {"query": "22047.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 648} 

WITH UserBadges AS (
  SELECT UserId, COUNT(*) AS BadgeCount, MAX(Class) AS BestClass
  FROM Badges
  GROUP BY UserId
),
PostStats AS (
  SELECT p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount,
         COUNT(c.Id) AS CommentCountOnPost,
         STRING_TO_ARRAY(NULLIF(SUBSTRING(p.Tags, 2, LENGTH(COALESCE(p.Tags, '<>')) - 2), ''), '><') AS TagArray,
         CASE WHEN p.ClosedDate IS NULL THEN 0 ELSE 1 END AS IsClosed
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  WHERE p.PostTypeId = 1
  GROUP BY p.Id, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount, p.Tags, p.ClosedDate
),
AnswerStats AS (
  SELECT a.ParentId, SUM(a.Score) AS TotalAnswerScore,
         AVG(COALESCE(a.Score, 0)) AS AvgAnswerScore
  FROM Posts a
  WHERE a.PostTypeId = 2
  GROUP BY a.ParentId
),
EditorHistory AS (
  SELECT ph.PostId, ph.UserId AS EditorId, COUNT(*) AS EditCount
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  GROUP BY ph.PostId, ph.UserId
)
SELECT u.DisplayName, COALESCE(ub.BadgeCount, 0) AS BadgeCount, ps.Score AS QuestionScore, 
       COALESCE(asq.TotalAnswerScore, 0) AS TotalAnswerScore,
       RANK() OVER (ORDER BY (COALESCE(asq.TotalAnswerScore, 0) + ps.Score + (CASE WHEN ps.ViewCount > 10000 THEN 1000 ELSE 0 END)) DESC) AS Rank,
       CASE WHEN LENGTH(COALESCE(u.Location, '')) > 5 THEN u.Location ELSE CONCAT('Area: ', COALESCE(u.Location, 'Unknown')) END AS Location,
       ps.TagArray[1] AS FirstTag,
       COALESCE(ps.CommentCountOnPost, 0) AS CommentsOnQuestion,
       ps.IsClosed,
       eh.EditCount AS EditsByOwner
FROM Users u
LEFT JOIN UserBadges ub ON ub.UserId = u.Id
INNER JOIN PostStats ps ON ps.OwnerUserId = u.Id
LEFT JOIN AnswerStats asq ON asq.ParentId = ps.Id
LEFT JOIN EditorHistory eh ON eh.PostId = ps.Id AND eh.EditorId = u.Id
WHERE (ub.BestClass <= 2 OR u.Reputation > 1000) 
  AND NOT EXISTS (
    SELECT 1 FROM Votes v WHERE v.PostId = ps.Id AND v.VoteTypeId = 12 -- Spam votes
  )
  AND EXISTS (
    SELECT 1 FROM PostLinks pl WHERE pl.PostId = ps.Id OR pl.RelatedPostId = ps.Id
  )
ORDER BY Rank
LIMIT 100;
