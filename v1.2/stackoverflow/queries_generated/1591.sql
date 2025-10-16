-- {"query": "1591.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1586} 

WITH RECURSIVE UserBadgeAggregate AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    b.Class,
    COUNT(*) AS BadgeCount,
    MIN(b.Date) AS FirstBadgeDate,
    MAX(b.Date) AS LastBadgeDate
  FROM Users u
  LEFT JOIN Badges b
    ON b.UserId = u.Id AND b.TagBased = 0
  WHERE u.Reputation > 500
  GROUP BY u.Id, u.DisplayName, b.Class
  
  UNION ALL
  
  SELECT
    uba.UserId,
    uba.DisplayName,
    CASE WHEN uba.Class = 3 THEN 2 ELSE uba.Class + 1 END,
    uba.BadgeCount * 2,
    uba.FirstBadgeDate,
    uba.LastBadgeDate
  FROM UserBadgeAggregate uba
  WHERE uba.Class < 3
),
TopQuestionsWithAvgScores AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.Score,
    u.DisplayName AS OwnerName,
    AVG(COALESCE(a.Score, 0)) OVER(PARTITION BY p.Id) AS AvgAnswerScore,
    MAX(v.CreationDate) FILTER (WHERE v.VoteTypeId=2) OVER(PARTITION BY p.Id) AS LastUpvoteDate
  FROM Posts p
  LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId=2
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId = 1 
    AND p.Tags ~ '(^|<)sql(<|$)'
    AND p.Score >= (
      SELECT PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY Score)
      FROM Posts WHERE PostTypeId = 1
    )
),
QuestionCommentSummary AS (
  SELECT
    c.PostId,
    COUNT(*) AS TotalComments,
    SUM(CASE WHEN c.SANITIZED_Text LIKE '%timeout%' OR c.Text ILIKE '%deadlock%' THEN 1 ELSE 0 END) AS ComplexityFlags,
    MAX(c.CreationDate) AS LastCommentDate
  FROM Comments c
  GROUP BY c.PostId
),
LatestPostHistoryPerPost AS (
  SELECT DISTINCT ON (ph.PostId) ph.PostId, ph.Id, ph.PostHistoryTypeId, ph.CreationDate, ph.UserId, ph.Comment
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13) -- post closed/reopened/deleted/undeleted
    AND ph.Comment IS NOT NULL
  ORDER BY ph.PostId, ph.CreationDate DESC
),
UserActivityRanking AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT q.Id) AS QuestionsCount,
    COUNT(DISTINCT a.Id) AS AnswersCount,
    ROW_NUMBER() OVER(PARTITION BY u.Location ORDER BY u.Reputation DESC) AS ReputationRankInLocation,
    PERCENT_RANK() OVER(ORDER BY u.UpVotes) AS UpvotePercentRank,
    SUM(v.BountyAmount) FILTER (WHERE v.VoteTypeId IN (8,9)) AS TotalBountyReceived
  FROM Users u
  LEFT JOIN Posts q ON q.OwnerUserId = u.Id AND q.PostTypeId=1
  LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId=2
  LEFT JOIN Votes v ON v.UserId = u.Id
  WHERE u.Reputation > 1000
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location
),
AllLinkedPostPairs AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    lt.Name as LinkType,
    pt1.PostTypeId as SourceType,
    pt2.PostTypeId as RelatedType,
    pt1.Title as SourceTitle,
    pt2.Title as RelatedTitle
  FROM PostLinks pl
  JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  JOIN Posts pt1 ON pt1.Id = pl.PostId
  JOIN Posts pt2 ON pt2.Id = pl.RelatedPostId
),
DuplicatedQuestionsAnswers AS (
  SELECT distinct q.Id AS QuestionId, q.Title,
    EXISTS (
      SELECT 1 
      FROM AllLinkedPostPairs p
      WHERE p.PostId = q.Id AND p.LinkType = 'Duplicate'
    ) AS IsMarkedDuplicate,
    COALESCE(
      (
        SELECT SUM(a.Score) FROM Posts a WHERE a.ParentId = q.Id
      ), 0) AS SumAnswerScore
  FROM Posts q
  WHERE q.PostTypeId = 1
)

SELECT 
  q.Id as QuestionId,
  q.Title,
  SUBSTR(REGEXP_REPLACE(q.Title, '[^A-Za-z0-9 ]', '', 'g'), 1, 60) || '...' AS AbbreviatedTitle,
  q.Score,
  q.ViewCount,
  q.OwnerName,
  ua.DisplayName AS TopContributor,
  ua.ReputationRankInLocation,
  ccs.TotalComments,
  CASE 
    WHEN ccs.ComplexityFlags > 0 THEN 'Possibly Complex'
    ELSE 'Simple'
  END AS ComplexityFlag,
  lpp.LinkType,
  COALESCE(uba.BadgeCount, 0) AS BadgesEarned,
  ostat.PatchCount,
  dubq.IsMarkedDuplicate,
  dubq.SumAnswerScore,
  phph.PostHistoryTypeId,
  phph.Comment as CloseReasonOrAction,
  phph.CreationDate AS LastClosureActivity,
  SL.annotated_score,
  SL.row_num
FROM TopQuestionsWithAvgScores q
LEFT JOIN QuestionCommentSummary ccs ON ccs.PostId = q.Id
LEFT JOIN UserActivityRanking ua ON ua.Id = q.OwnerUserId
LEFT JOIN LatestPostHistoryPerPost phph ON phph.PostId = q.Id
LEFT JOIN DuplicatedQuestionsAnswers dubq ON dubq.QuestionId = q.Id
LEFT JOIN (
  SELECT UserId, SUM(BadgeCount) AS BadgeCount
  FROM UserBadgeAggregate
  GROUP BY UserId
) uba ON uba.UserId = q.OwnerUserId
LEFT JOIN LATERAL (
  SELECT
    Score as annotated_score,  
    ROW_NUMBER() OVER(PARTITION BY OwnerName ORDER BY Score DESC) as row_num
  FROM Posts
  WHERE Tags LIKE '%<>%sql<>%'
    AND OwnerUserId = q.OwnerUserId
    AND Score > 0
  ORDER BY Score DESC
  LIMIT 1
) SL ON TRUE
LEFT JOIN LATERAL (
  SELECT COUNT(*) FILTER (WHERE PostHistoryTypeId IN (4,5,6)) AS PatchCount FROM PostHistory ph WHERE ph.PostId = q.Id
) ostat ON TRUE
LEFT JOIN LATERAL (
  SELECT LinkType
  FROM AllLinkedPostPairs pl
  WHERE pl.PostId = q.Id
  ORDER BY LinkType LIMIT 1
) lpp ON TRUE
WHERE q.LastUpvoteDate > now() - INTERVAL '6 months'
  AND (
    q.AvgAnswerScore > 5
    OR ccs.TotalComments > 10
  )
   AND NULLIF(trim(dubq.Comment), '') IS DISTINCT FROM '100' -- filtering potential filtered close reason id '100'
ORDER BY ua.ReputationRankInLocation, q.Score DESC NULLS LAST
LIMIT 50;
