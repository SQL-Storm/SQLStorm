WITH
  RankedAnswers AS (
    SELECT
      p.Id AS PostId,
      p.ParentId AS QuestionId,
      p.OwnerUserId,
      p.CreationDate AS AnswerCreationDate,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS RankByScore,
      COUNT(c.Id) OVER (PARTITION BY p.ParentId) AS CommentCountOnQuestion,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.ParentId) AS UpvotesOnQuestion,
      LAG(p.Score, 1, 0) OVER (PARTITION BY p.ParentId ORDER BY p.CreationDate) AS PreviousAnswerScore,
      LEAD(p.Score, 1, 0) OVER (PARTITION BY p.ParentId ORDER BY p.CreationDate) AS NextAnswerScore
    FROM Posts p
    LEFT JOIN Comments c
      ON p.ParentId = c.PostId
    LEFT JOIN Votes v
      ON p.ParentId = v.PostId AND v.VoteTypeId = 2
    WHERE
      p.PostTypeId = 2 AND p.ParentId IS NOT NULL AND p.OwnerUserId IS NOT NULL
  ),
  QuestionEngagement AS (
    SELECT
      q.Id AS QuestionId,
      q.OwnerUserId AS QuestionOwnerUserId,
      q.CreationDate AS QuestionCreationDate,
      q.Score AS QuestionScore,
      q.ViewCount AS QuestionViewCount,
      q.AnswerCount AS QuestionAnswerCount,
      q.FavoriteCount AS QuestionFavoriteCount,
      q.ClosedDate,
      CASE WHEN q.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS QuestionStatus,
      COUNT(DISTINCT ph.Id) AS PostHistoryCount,
      SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
      AVG(ra.RankByScore) AS AvgAnswerRank,
      MAX(ra.AnswerCreationDate) AS LastAnswerDate,
      MIN(ra.AnswerCreationDate) AS FirstAnswerDate,
      (
        SELECT
          MAX(ph2.CreationDate)
        FROM PostHistory ph2
        WHERE
          ph2.PostId = q.Id AND ph2.PostHistoryTypeId = 6
      ) AS LastTagEditDate,
      COALESCE(u.DisplayName, 'Unknown User') AS QuestionOwnerDisplayName,
      u.Reputation AS QuestionOwnerReputation,
      u.UpVotes AS QuestionOwnerUpVotes,
      u.DownVotes AS QuestionOwnerDownVotes,
      CAST((CAST('2024-10-01 12:34:56' AS timestamp) - q.CreationDate) AS interval) AS _tmp_interval,
      EXTRACT(epoch FROM CAST((CAST('2024-10-01 12:34:56' AS timestamp) - q.CreationDate) AS interval)) / 86400 AS DaysSinceCreation
    FROM Posts q
    LEFT JOIN PostHistory ph
      ON q.Id = ph.PostId
    LEFT JOIN Users u
      ON q.OwnerUserId = u.Id
    LEFT JOIN RankedAnswers ra
      ON q.Id = ra.QuestionId
    WHERE
      q.PostTypeId = 1
    GROUP BY
      q.Id,
      q.OwnerUserId,
      q.CreationDate,
      q.Score,
      q.ViewCount,
      q.AnswerCount,
      q.FavoriteCount,
      q.ClosedDate,
      u.DisplayName,
      u.Reputation,
      u.UpVotes,
      u.DownVotes
  )
SELECT
  qe.QuestionId,
  qe.QuestionOwnerDisplayName,
  qe.QuestionOwnerReputation,
  qe.QuestionStatus,
  qe.QuestionScore,
  qe.QuestionViewCount,
  qe.QuestionAnswerCount,
  qe.QuestionFavoriteCount,
  qe.PostHistoryCount,
  qe.EditCount,
  qe.AvgAnswerRank,
  qe.LastAnswerDate,
  qe.FirstAnswerDate,
  qe.LastTagEditDate,
  qe.DaysSinceCreation,
  CASE
    WHEN qe.QuestionScore > 50 AND qe.QuestionViewCount > 10000 AND qe.QuestionAnswerCount > 5 THEN 'High Engagement'
    WHEN qe.QuestionScore < 0 AND qe.ClosedDate IS NOT NULL THEN 'Potentially Problematic'
    WHEN qe.QuestionOwnerReputation < 500 AND qe.EditCount > 3 THEN 'New User, Active Editor'
    ELSE 'Standard'
  END AS EngagementCategory,
  CASE
    WHEN qe.LastTagEditDate IS NOT NULL AND qe.QuestionCreationDate IS NOT NULL THEN
      EXTRACT(epoch FROM (qe.LastTagEditDate - qe.QuestionCreationDate)) / 86400
    ELSE NULL
  END AS DaysBetweenCreationAndLastTagEdit,
  UPPER(SUBSTRING(qe.QuestionOwnerDisplayName FROM 1 FOR 3)) AS OwnerInitials,
  CASE WHEN qe.QuestionOwnerDownVotes IS NOT NULL AND qe.QuestionOwnerDownVotes <> 0 AND qe.QuestionOwnerUpVotes * 1.0 / qe.QuestionOwnerDownVotes > 2 THEN 'High Upvote Ratio' ELSE 'Standard Ratio' END AS OwnerVoteRatio,
  (CAST(qe.QuestionId AS text) || '-' || CAST(qe.QuestionOwnerUserId AS text)) AS CompositeKey,
  COALESCE(qe.ClosedDate, qe.QuestionCreationDate) AS EffectiveDate,
  (SELECT COUNT(DISTINCT Id) FROM Comments WHERE PostId = qe.QuestionId) AS DirectCommentCount,
  (
    SELECT
      SUM(Score)
    FROM Posts ans
    WHERE
      ans.ParentId = qe.QuestionId
  ) AS TotalAnswerScore,
  qe.QuestionOwnerReputation + qe.QuestionOwnerUpVotes - qe.QuestionOwnerDownVotes AS NetUserScore
FROM QuestionEngagement qe
WHERE
  qe.QuestionScore > -5
  AND qe.QuestionViewCount > 100
  AND qe.DaysSinceCreation > 7
  AND qe.QuestionOwnerDisplayName NOT LIKE '%Community%'
UNION
SELECT
  qe.QuestionId,
  qe.QuestionOwnerDisplayName,
  qe.QuestionOwnerReputation,
  qe.QuestionStatus,
  qe.QuestionScore,
  qe.QuestionViewCount,
  qe.QuestionAnswerCount,
  qe.QuestionFavoriteCount,
  qe.PostHistoryCount,
  qe.EditCount,
  qe.AvgAnswerRank,
  qe.LastAnswerDate,
  qe.FirstAnswerDate,
  qe.LastTagEditDate,
  qe.DaysSinceCreation,
  CASE
    WHEN qe.QuestionScore > 50 AND qe.QuestionViewCount > 10000 AND qe.QuestionAnswerCount > 5 THEN 'High Engagement'
    WHEN qe.QuestionScore < 0 AND qe.ClosedDate IS NOT NULL THEN 'Potentially Problematic'
    WHEN qe.QuestionOwnerReputation < 500 AND qe.EditCount > 3 THEN 'New User, Active Editor'
    ELSE 'Standard'
  END AS EngagementCategory,
  CASE
    WHEN qe.LastTagEditDate IS NOT NULL AND qe.QuestionCreationDate IS NOT NULL THEN
      EXTRACT(epoch FROM (qe.LastTagEditDate - qe.QuestionCreationDate)) / 86400
    ELSE NULL
  END AS DaysBetweenCreationAndLastTagEdit,
  UPPER(SUBSTRING(qe.QuestionOwnerDisplayName FROM 1 FOR 3)) AS OwnerInitials,
  CASE WHEN qe.QuestionOwnerDownVotes IS NOT NULL AND qe.QuestionOwnerDownVotes <> 0 AND qe.QuestionOwnerUpVotes * 1.0 / qe.QuestionOwnerDownVotes > 2 THEN 'High Upvote Ratio' ELSE 'Standard Ratio' END AS OwnerVoteRatio,
  (CAST(qe.QuestionId AS text) || '-' || CAST(qe.QuestionOwnerUserId AS text)) AS CompositeKey,
  COALESCE(qe.ClosedDate, qe.QuestionCreationDate) AS EffectiveDate,
  (SELECT COUNT(DISTINCT Id) FROM Comments WHERE PostId = qe.QuestionId) AS DirectCommentCount,
  (
    SELECT
      SUM(Score)
    FROM Posts ans
    WHERE
      ans.ParentId = qe.QuestionId
  ) AS TotalAnswerScore,
  qe.QuestionOwnerReputation + qe.QuestionOwnerUpVotes - qe.QuestionOwnerDownVotes AS NetUserScore
FROM QuestionEngagement qe
WHERE
  qe.QuestionScore <= -5
  AND qe.QuestionViewCount <= 100
  AND qe.DaysSinceCreation <= 7
  AND qe.QuestionOwnerDisplayName NOT LIKE '%Community%'
ORDER BY
  QuestionScore DESC,
  QuestionViewCount DESC;