WITH
  UserContributionSummary AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
      COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
      COUNT(DISTINCT b.Id) AS BadgeCount,
      MAX(b.Date) AS LastBadgeDate
    FROM Users u
    LEFT JOIN Posts p
      ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b
      ON u.Id = b.UserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation
  ),
  PostEngagement AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.Title,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.CommentCount,
      p.FavoriteCount,
      (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVoteCount,
      (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVoteCount,
      CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
      p.Tags
    FROM Posts p
    WHERE p.PostTypeId = 1
  ),
  UserPostInteraction AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount,
      MAX(ph.CreationDate) AS LastEditDate,
      COUNT(DISTINCT c.Id) AS CommentCount
    FROM Users u
    JOIN PostHistory ph
      ON u.Id = ph.UserId
    LEFT JOIN Comments c
      ON u.Id = c.UserId
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  TagPerformance AS (
    SELECT
      t.TagName,
      COUNT(DISTINCT p.Id) AS TagQuestionCount,
      AVG(p.Score) AS AverageQuestionScore,
      SUM(p.ViewCount) AS TotalTagViews
    FROM Tags t
    JOIN Posts p
      ON p.Tags LIKE '%' || t.TagName || '%' AND p.PostTypeId = 1
    GROUP BY
      t.TagName
  )
SELECT
  ucs.DisplayName,
  ucs.QuestionCount,
  ucs.AnswerCount,
  ucs.TotalAnswerScore,
  ucs.BadgeCount,
  ucs.LastBadgeDate,
  upi.EditCount,
  upi.LastEditDate,
  upi.CommentCount,
  pe.Title AS LatestQuestionTitle,
  pe.Score AS LatestQuestionScore,
  pe.ViewCount AS LatestQuestionViews,
  pe.UpVoteCount AS LatestQuestionUpVotes,
  pe.DownVoteCount AS LatestQuestionDownVotes,
  pe.IsClosed AS IsLatestQuestionClosed,
  tp.TagName,
  tp.TagQuestionCount,
  tp.AverageQuestionScore,
  tp.TotalTagViews,
  CASE
    WHEN ucs.LastBadgeDate > COALESCE(upi.LastEditDate, TIMESTAMP '1970-01-01') THEN 'Badges'
    ELSE 'Edits'
  END AS MostRecentActivityType,
  DENSE_RANK() OVER (ORDER BY ucs.Reputation DESC) AS ReputationRank,
  ROW_NUMBER() OVER (PARTITION BY tp.TagName ORDER BY pe.CreationDate DESC) AS QuestionSequenceInTag
FROM UserContributionSummary ucs
JOIN PostEngagement pe
  ON ucs.UserId = pe.OwnerUserId
LEFT JOIN UserPostInteraction upi
  ON ucs.UserId = upi.UserId
LEFT JOIN Tags t
  ON pe.Tags LIKE '%' || t.TagName || '%'
LEFT JOIN TagPerformance tp
  ON t.TagName = tp.TagName
WHERE
  ucs.AnswerCount > 50
  AND tp.TagQuestionCount > 1000
  AND ucs.DisplayName IS NOT NULL
  AND LENGTH(TRIM(ucs.DisplayName)) > 3
  AND COALESCE(ucs.TotalAnswerScore, 0) > 100
  AND pe.CreationDate > DATE '2022-01-01'
  AND (
    t.TagName <> 'sql' OR tp.AverageQuestionScore > 15
  )
GROUP BY
  ucs.DisplayName,
  ucs.QuestionCount,
  ucs.AnswerCount,
  ucs.TotalAnswerScore,
  ucs.BadgeCount,
  ucs.LastBadgeDate,
  upi.EditCount,
  upi.LastEditDate,
  upi.CommentCount,
  pe.Title,
  pe.Score,
  pe.ViewCount,
  pe.UpVoteCount,
  pe.DownVoteCount,
  pe.IsClosed,
  tp.TagName,
  tp.TagQuestionCount,
  tp.AverageQuestionScore,
  tp.TotalTagViews,
  ucs.Reputation,
  pe.CreationDate
ORDER BY
  ucs.TotalAnswerScore DESC,
  tp.AverageQuestionScore DESC
LIMIT 100;