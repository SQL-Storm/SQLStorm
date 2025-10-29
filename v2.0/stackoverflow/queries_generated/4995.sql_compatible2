WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  UserReputation AS (
    SELECT
      u.Id AS UserId,
      u.Reputation,
      u.UpVotes AS UserUpVotes,
      u.DownVotes AS UserDownVotes
    FROM Users u
  ),
  PostDetails AS (
    SELECT
      p.Id AS PostId,
      p.PostTypeId,
      p.OwnerUserId,
      p.CreationDate AS PostCreationDate,
      p.Score AS PostScore,
      p.ViewCount AS PostViewCount,
      p.FavoriteCount AS PostFavoriteCount,
      p.AnswerCount,
      p.CommentCount,
      pt.Name AS PostTypeName,
      CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed
    FROM Posts p
    JOIN PostTypes pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.PostTypeId IN (1, 2)
  ),
  RecentEdits AS (
    SELECT
      rpe.PostId,
      rpe.UserId AS LastEditorUserId,
      rpe.CreationDate AS LastEditDate,
      rpe.PostHistoryTypeId
    FROM RankedPostEdits rpe
    WHERE
      rpe.rn = 1
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.CreationDate AS UserCreationDate,
      COUNT(DISTINCT pd.PostId) AS TotalPosts,
      SUM(CASE WHEN pd.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN pd.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(pd.PostScore) AS AvgPostScore,
      SUM(pd.PostFavoriteCount) AS TotalFavorites,
      SUM(CASE WHEN pd.IsClosed = 1 THEN 1 ELSE 0 END) AS ClosedPostsCount,
      MAX(pd.PostCreationDate) AS LastPostCreationDate
    FROM Users u
    LEFT JOIN PostDetails pd
      ON u.Id = pd.OwnerUserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.CreationDate
  ),
  QuestionStats AS (
    SELECT
      pd.PostId,
      pd.PostScore,
      pd.PostViewCount,
      pd.AnswerCount,
      pd.CommentCount,
      pd.IsClosed,
      ROW_NUMBER() OVER (ORDER BY pd.PostScore DESC) AS ScoreRank,
      DENSE_RANK() OVER (PARTITION BY pd.IsClosed ORDER BY pd.PostViewCount DESC) AS ViewCountRankPerCloseStatus,
      LAG(pd.PostCreationDate, 1, pd.PostCreationDate) OVER (ORDER BY pd.PostCreationDate) AS PreviousPostCreationDate,
      pd.PostCreationDate AS PostCreationDate
    FROM PostDetails pd
    WHERE
      pd.PostTypeId = 1
  ),
  AnswerStats AS (
    SELECT
      pd.PostId,
      pd.PostScore,
      pd.CommentCount,
      pd.OwnerUserId,
      ROW_NUMBER() OVER (PARTITION BY pd.OwnerUserId ORDER BY pd.PostScore DESC) AS ScoreRankPerUser,
      COUNT(pd.PostId) OVER (PARTITION BY pd.OwnerUserId) AS AnswersPerUser
    FROM PostDetails pd
    WHERE
      pd.PostTypeId = 2
  ),
  UserAwards AS (
    SELECT
      b.UserId,
      COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
      COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
      COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY
      b.UserId
  )
SELECT
  COALESCE(ua.DisplayName, 'Community') AS UserName,
  ua.UserCreationDate,
  COALESCE(ua.TotalPosts, 0) AS UserTotalPosts,
  COALESCE(ua.QuestionCount, 0) AS UserQuestionCount,
  COALESCE(ua.AnswerCount, 0) AS UserAnswerCount,
  COALESCE(CAST(ua.AvgPostScore AS DECIMAL(10, 2)), 0.00) AS UserAvgPostScore,
  COALESCE(ua.TotalFavorites, 0) AS UserTotalFavorites,
  COALESCE(ua.ClosedPostsCount, 0) AS UserClosedPostCount,
  COALESCE(CAST(ur.Reputation AS BIGINT), 0) AS UserReputation,
  COALESCE(ur.UserUpVotes, 0) AS UserTotalUpVotes,
  COALESCE(ur.UserDownVotes, 0) AS UserTotalDownVotes,
  COALESCE(CAST(q.PostScore AS INT), 0) AS TopQuestionScore,
  COALESCE(CAST(q.PostViewCount AS INT), 0) AS TopQuestionViews,
  COALESCE(CAST(q.AnswerCount AS INT), 0) AS TopQuestionAnswers,
  COALESCE(CAST(q.CommentCount AS INT), 0) AS TopQuestionComments,
  q.ScoreRank AS TopQuestionScoreRank,
  q.ViewCountRankPerCloseStatus AS TopQuestionViewRank,
  CASE
    WHEN q.PreviousPostCreationDate IS NULL OR q.PostCreationDate IS NULL THEN NULL
    ELSE CAST(EXTRACT(EPOCH FROM (q.PostCreationDate - q.PreviousPostCreationDate)) / 86400 AS INTEGER)
  END AS DaysSincePreviousQuestion,
  COALESCE(a.ScoreRankPerUser, 0) AS AnswerScoreRankForUser,
  COALESCE(a.AnswersPerUser, 0) AS AnswersCountForUser,
  COALESCE(re.LastEditDate, pd.PostCreationDate) AS PostLastEditOrCreationDate,
  COALESCE(re.PostHistoryTypeId, 0) AS PostLastEditTypeId,
  COALESCE(uae.GoldBadges, 0) AS UserGoldBadges,
  COALESCE(uae.SilverBadges, 0) AS UserSilverBadges,
  COALESCE(uae.BronzeBadges, 0) AS UserBronzeBadges,
  CASE
    WHEN ua.LastPostCreationDate IS NULL THEN NULL
    WHEN ua.LastPostCreationDate < (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1' YEAR) THEN 'Inactive'
    ELSE 'Active'
  END AS UserActivityStatus,
  CASE
    WHEN pd.PostTypeName IS NULL THEN 'Unknown'
    ELSE pd.PostTypeName
  END AS PostType,
  CASE
    WHEN pd.IsClosed = 1 THEN 'Closed'
    ELSE 'Open'
  END AS PostStatus,
  UPPER(SUBSTR(COALESCE(pd.PostTypeName, 'N/A'), 1, 3)) AS PostTypeAbbreviation,
  (COALESCE(CAST(pd.PostScore AS VARCHAR), '0') || '|' || COALESCE(CAST(pd.PostViewCount AS VARCHAR), '0')) AS ScoreAndViewCountConcat,
  CASE
    WHEN pd.OwnerUserId IS NULL THEN 'Community'
    WHEN pd.OwnerUserId = -1 THEN 'Community'
    ELSE CAST(pd.OwnerUserId AS VARCHAR)
  END AS PostOwnerIdentifier,
  CASE
    WHEN (ua.TotalPosts > 1000 AND ua.AvgPostScore > 50) OR COALESCE(uae.GoldBadges, 0) > 5 THEN 'Power User'
    WHEN ua.TotalPosts > 100 AND ua.AvgPostScore > 10 THEN 'Experienced User'
    ELSE 'Regular User'
  END AS UserTier,
  CAST(ua.UserCreationDate AS DATE) AS UserCreationDateOnly,
  EXTRACT(year FROM ua.UserCreationDate) AS UserCreationYear,
  EXTRACT(month FROM ua.UserCreationDate) AS UserCreationMonth
FROM UserActivity ua
FULL OUTER JOIN UserReputation ur
  ON ua.UserId = ur.UserId
FULL OUTER JOIN PostDetails pd
  ON ua.UserId = pd.OwnerUserId
LEFT JOIN RecentEdits re
  ON pd.PostId = re.PostId
LEFT JOIN QuestionStats q
  ON pd.PostId = q.PostId AND pd.PostTypeId = 1
LEFT JOIN AnswerStats a
  ON pd.PostId = a.PostId AND pd.PostTypeId = 2
LEFT JOIN UserAwards uae
  ON ua.UserId = uae.UserId
WHERE
  (ua.UserId IS NOT NULL OR pd.PostId IS NOT NULL)
  AND (
    pd.PostId IS NULL
    OR (pd.PostTypeId = 1 AND q.ScoreRank <= 100)
    OR (pd.PostTypeId = 2 AND a.AnswersPerUser > 5)
  )
ORDER BY
  UserTier DESC,
  UserReputation DESC,
  ua.TotalPosts DESC
LIMIT 1000;