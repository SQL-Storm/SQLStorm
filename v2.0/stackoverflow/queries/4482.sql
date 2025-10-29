WITH
  AggregatedPostStats AS (
    SELECT
      p.Id AS PostId,
      p.PostTypeId,
      pt.Name AS PostTypeName,
      p.OwnerUserId,
      u.DisplayName AS OwnerDisplayName,
      p.CreationDate AS PostCreationDate,
      p.Score AS PostScore,
      p.ViewCount AS PostViewCount,
      p.AnswerCount AS PostAnswerCount,
      p.CommentCount AS PostCommentCount,
      p.FavoriteCount AS PostFavoriteCount,
      p.ClosedDate AS PostClosedDate,
      CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS UserPostSequence,
      LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore,
      SUM(CASE WHEN c.Id IS NOT NULL THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS CommentCountForPost,
      AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgUserPostScore
    FROM Posts p
    JOIN PostTypes pt
      ON p.PostTypeId = pt.Id
    LEFT JOIN Users u
      ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c
      ON p.Id = c.PostId
    WHERE
      p.PostTypeId IN (1, 2) AND p.CreationDate >= DATE '2023-01-01'
  ),
  HighEngagementUsers AS (
    SELECT DISTINCT
      OwnerUserId
    FROM AggregatedPostStats
    WHERE
      PostScore > 10 AND PostAnswerCount > 5
  ),
  RecentQuestions AS (
    SELECT
      Id,
      OwnerUserId,
      Title,
      Tags,
      CreationDate,
      Score,
      ViewCount,
      AnswerCount,
      ClosedDate
    FROM Posts
    WHERE
      PostTypeId = 1 AND CreationDate >= cast('2024-10-01' as date) - INTERVAL '30' DAY
  ),
  TagScores AS (
    SELECT
      SUBSTRING(t.TagName FROM 2 FOR CHAR_LENGTH(t.TagName) - 2) AS TagName,
      SUM(p.Score) AS TotalScore,
      COUNT(p.Id) AS QuestionCount
    FROM Posts p
    JOIN Tags t
      ON CONCAT(',', REPLACE(p.Tags, '><', ','), ',') LIKE CONCAT('%,', t.TagName, ',%')
    WHERE
      p.PostTypeId = 1 AND p.CreationDate >= DATE '2023-01-01'
    GROUP BY
      t.TagName
  ),
  UserTagActivity AS (
    SELECT
      u.Id AS UserId,
      SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags) - 2) AS TagName,
      COUNT(p.Id) AS UserQuestionCount,
      SUM(p.Score) AS UserTotalScore
    FROM Posts p
    JOIN Users u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1 AND p.CreationDate >= DATE '2023-01-01' AND u.Id IN (SELECT OwnerUserId FROM HighEngagementUsers)
    GROUP BY
      u.Id,
      SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags) - 2)
  )
SELECT
  q.Id AS QuestionId,
  q.Title AS QuestionTitle,
  q.OwnerUserId,
  u.DisplayName AS QuestionOwnerDisplayName,
  q.CreationDate AS QuestionCreationDate,
  q.Score AS QuestionScore,
  q.ViewCount AS QuestionViewCount,
  q.AnswerCount AS QuestionAnswerCount,
  COALESCE(q.AnswerCount, 0) AS NonNullAnswerCount,
  aps.PostTypeName,
  aps.IsClosed,
  aps.UserPostSequence,
  aps.PreviousPostScore,
  aps.AvgUserPostScore,
  aps.CommentCountForPost,
  COUNT(DISTINCT p_ans.Id) AS AnswerCountDirect,
  SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateLinkCount,
  CASE WHEN q.OwnerUserId IN (SELECT UserId FROM Badges WHERE Name LIKE '%Master%') THEN 'Yes' ELSE 'No' END AS HasMasterBadge,
  ts.TotalScore AS TopTagScore,
  ts.QuestionCount AS TopTagQuestionCount,
  uta.UserQuestionCount AS UserSpecificTagQuestionCount,
  uta.UserTotalScore AS UserSpecificTagScore,
  CASE
    WHEN q.OwnerUserId IS NULL THEN 'Community'
    WHEN q.OwnerUserId = -1 THEN 'Community'
    WHEN q.OwnerUserId = 0 THEN 'Anonymous'
    ELSE u.DisplayName
  END AS SafeOwnerDisplayName,
  UPPER(SUBSTRING(q.Title FROM 1 FOR 3)) AS TitlePrefix,
  CASE
    WHEN q.Tags LIKE '%<sql>%' THEN 'SQL Related'
    WHEN q.Tags LIKE '%<python>%' THEN 'Python Related'
    ELSE 'Other'
  END AS TagCategory,
  CONCAT(COALESCE(CAST(q.Score AS VARCHAR), 'N/A'), ' - ', COALESCE(u.DisplayName, 'Unknown')) AS ScoreAndOwner,
  CASE
    WHEN q.ClosedDate IS NOT NULL AND q.ClosedDate < (cast('2024-10-01' as date) - INTERVAL '7' DAY) THEN 'Old Closed Question'
    WHEN q.ClosedDate IS NOT NULL THEN 'Recent Closed Question'
    WHEN q.AnswerCount > 50 THEN 'High Answer Count'
    ELSE 'Standard Question'
  END AS QuestionStatus
FROM RecentQuestions q
LEFT JOIN AggregatedPostStats aps
  ON q.Id = aps.PostId
LEFT JOIN Users u
  ON q.OwnerUserId = u.Id
LEFT JOIN Posts p_ans
  ON q.Id = p_ans.ParentId AND p_ans.PostTypeId = 2
LEFT JOIN PostLinks pl
  ON q.Id = pl.PostId AND pl.LinkTypeId = 3
LEFT JOIN TagScores ts
  ON CONCAT(',', REPLACE(q.Tags, '><', ','), ',') LIKE CONCAT('%,', ts.TagName, ',%') AND ts.TagName IN ('sql', 'python', 'javascript')
LEFT JOIN UserTagActivity uta
  ON q.OwnerUserId = uta.UserId AND uta.TagName IN ('sql', 'python', 'javascript')
WHERE
  q.Score > 0 AND q.ViewCount > 100
GROUP BY
  q.Id,
  q.Title,
  q.OwnerUserId,
  u.DisplayName,
  q.CreationDate,
  q.Score,
  q.ViewCount,
  q.AnswerCount,
  aps.PostTypeName,
  aps.IsClosed,
  aps.UserPostSequence,
  aps.PreviousPostScore,
  aps.AvgUserPostScore,
  aps.CommentCountForPost,
  ts.TotalScore,
  ts.QuestionCount,
  uta.UserQuestionCount,
  uta.UserTotalScore,
  q.ClosedDate,
  q.Tags
ORDER BY
  q.CreationDate DESC
LIMIT 1000;