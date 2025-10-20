WITH RecursivePostCounts AS (
  SELECT 
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.Score,
    p.AnswerCount,
    COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id), 0) AS CommentsCount
  FROM Posts p
)
SELECT
  prs.Id,
  COALESCE(ups.Reputation, 0) AS Reputation
FROM RecursivePostCounts prs
LEFT JOIN Users ups
  ON prs.OwnerUserId = ups.Id
GROUP BY
  prs.Id,
  prs.Title,
  prs.OwnerUserId,
  prs.Score,
  prs.AnswerCount,
  prs.CommentsCount,
  ups.Reputation;