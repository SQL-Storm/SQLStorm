WITH
  RecentQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.Title,
      p.OwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      p.FavoriteCount,
      p.AnswerCount,
      p.Score AS QuestionScore,
      u.DisplayName AS OwnerDisplayName,
      u.Reputation AS OwnerReputation,
      ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
    FROM
      Posts p
      JOIN Users u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30' DAY
  ),
  HighEngagementAnswers AS (
    SELECT
      p.ParentId AS QuestionId,
      COUNT(p.Id) AS AnswerCount,
      SUM(p.Score) AS TotalAnswerScore,
      AVG(p.Score) AS AvgAnswerScore,
      MAX(p.CreationDate) AS LastAnswerDate,
      COUNT(DISTINCT ph.UserId) AS DistinctAnswererCount
    FROM
      Posts p
      LEFT JOIN PostHistory ph
      ON p.Id = ph.PostId
      AND ph.PostHistoryTypeId IN (2, 5)
    WHERE
      p.PostTypeId = 2
    GROUP BY
      p.ParentId
  ),
  TopVotedAnswers AS (
    SELECT
      a.QuestionId,
      a.AnswerId,
      a.AnswerScore,
      a.AnswerCreationDate,
      a.AnswerOwnerDisplayName,
      a.AnswerOwnerReputation,
      DENSE_RANK() OVER (PARTITION BY a.QuestionId ORDER BY a.AnswerScore DESC) AS RankByScore
    FROM
      (
        SELECT
          p.ParentId AS QuestionId,
          p.Id AS AnswerId,
          p.Score AS AnswerScore,
          p.CreationDate AS AnswerCreationDate,
          u.DisplayName AS AnswerOwnerDisplayName,
          u.Reputation AS AnswerOwnerReputation
        FROM
          Posts p
          JOIN Users u
          ON p.OwnerUserId = u.Id
        WHERE
          p.PostTypeId = 2
      ) a
  ),
  CommentAnalysis AS (
    SELECT
      c.PostId,
      COUNT(c.Id) AS CommentCount,
      SUM(c.Score) AS TotalCommentScore,
      AVG(LENGTH(c.Text)) AS AvgCommentLength,
      MAX(c.CreationDate) AS LastCommentDate
    FROM
      Comments c
    WHERE
      c.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30' DAY
    GROUP BY
      c.PostId
  ),
  PostTagAnalysis AS (
    SELECT
      p.Id AS PostId,
      COUNT(DISTINCT t.TagName) AS TagCount,
      STRING_AGG(t.TagName, ',' ORDER BY t.TagName) AS TagList,
      CASE
        WHEN POSITION('<sql>' IN COALESCE(p.Tags, '')) > 0 THEN 'Has SQL Tag'
        WHEN POSITION('<python>' IN COALESCE(p.Tags, '')) > 0 THEN 'Has Python Tag'
        ELSE 'Other Tags'
      END AS PrimaryTagCategory,
      CASE
        WHEN p.Tags IS NULL THEN 0
        ELSE CHAR_LENGTH(p.Tags) - CHAR_LENGTH(REPLACE(p.Tags, '><', '')) + 1
      END AS NumberOfTags
    FROM
      Posts p
      LEFT JOIN (
        SELECT
          Id,
          CASE
            WHEN Tags IS NOT NULL THEN
              SUBSTRING(Tags FROM POSITION('<' IN Tags) + 1 FOR POSITION('>' IN Tags) - POSITION('<' IN Tags) - 1)
          END AS TagName
        FROM
          Posts
        WHERE
          Tags IS NOT NULL
      ) t
      ON p.Id = t.Id
    WHERE
      p.PostTypeId = 1
    GROUP BY
      p.Id,
      p.Tags,
      p.PostTypeId
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS QuestionCount,
      COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS AnswerCount,
      COUNT(DISTINCT c.Id) AS CommentCount,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
      MAX(u.CreationDate) AS UserCreationDate,
      CAST(DATE_PART('day', CAST('2024-10-01' AS date) - MAX(u.CreationDate)) AS bigint) AS DaysSinceCreation
    FROM
      Users u
      LEFT JOIN Posts p
      ON u.Id = p.OwnerUserId
      LEFT JOIN Comments c
      ON u.Id = c.UserId
      LEFT JOIN Votes v
      ON u.Id = v.UserId
    WHERE
      u.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '180' DAY
    GROUP BY
      u.Id,
      u.DisplayName,
      u.CreationDate
    HAVING
      COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) > 5
      OR COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) > 10
  )
SELECT
  rq.QuestionId AS QuestionId,
  rq.Title,
  rq.OwnerDisplayName,
  rq.OwnerReputation,
  rq.QuestionCreationDate,
  rq.FavoriteCount,
  rq.AnswerCount AS TotalAnswers,
  rq.QuestionScore,
  COALESCE(hga.AnswerCount, 0) AS AnswerCountFromHighEngagement,
  COALESCE(hga.TotalAnswerScore, 0) AS TotalAnswerScore,
  COALESCE(hga.AvgAnswerScore, 0.0) AS AvgAnswerScore,
  COALESCE(ca.CommentCount, 0) AS CommentCountOnQuestion,
  COALESCE(ca.TotalCommentScore, 0) AS TotalCommentScoreOnQuestion,
  COALESCE(ca.AvgCommentLength, 0.0) AS AvgCommentLengthOnQuestion,
  pt.TagList,
  pt.PrimaryTagCategory,
  pt.NumberOfTags,
  tva.AnswerId AS TopAnswerId,
  tva.AnswerScore AS TopAnswerScore,
  tva.AnswerOwnerDisplayName AS TopAnswerOwner,
  tva.AnswerOwnerReputation AS TopAnswerReputation,
  ua.QuestionCount AS UserQuestionActivity,
  ua.AnswerCount AS UserAnswerActivity,
  ua.CommentCount AS UserCommentActivity,
  ua.UpVoteCount AS UserUpVotes,
  ua.DownVoteCount AS UserDownVotes,
  ua.DaysSinceCreation AS UserAccountAgeInDays,
  CASE
    WHEN rq.QuestionScore > 100 AND COALESCE(hga.AnswerCount, 0) > 5 THEN 'Highly Rated Question with Many Answers'
    WHEN rq.FavoriteCount > 50 AND COALESCE(pt.NumberOfTags, 0) < 5 THEN 'Popular but Niche Question'
    WHEN COALESCE(ua.UpVoteCount, 0) > COALESCE(ua.DownVoteCount, 0) * 2 AND ua.DaysSinceCreation < 365 THEN 'Promising New User'
    WHEN rq.QuestionCreationDate < CAST('2024-10-01' AS date) - INTERVAL '365' DAY AND rq.AnswerCount = 0 THEN 'Old Unanswered Question'
    ELSE 'Standard Question'
  END AS PerformanceCategory
FROM
  RecentQuestions rq
  LEFT JOIN HighEngagementAnswers hga
  ON rq.QuestionId = hga.QuestionId
  LEFT JOIN CommentAnalysis ca
  ON rq.QuestionId = ca.PostId
  LEFT JOIN PostTagAnalysis pt
  ON rq.QuestionId = pt.PostId
  LEFT JOIN TopVotedAnswers tva
  ON rq.QuestionId = tva.QuestionId AND tva.RankByScore = 1
  LEFT JOIN UserActivity ua
  ON rq.OwnerUserId = ua.UserId
WHERE
  rq.rn <= 100
  AND rq.QuestionScore IS NOT NULL
  AND rq.AnswerCount IS NOT NULL
  AND rq.OwnerUserId IS NOT NULL;