WITH
  UserPostInteractions AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.PostTypeId,
      p.Score,
      p.CommentCount,
      p.FavoriteCount,
      p.CreationDate AS PostCreationDate,
      COUNT(DISTINCT c.Id) AS CommentCountForPost,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCountForPost,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCountForPost,
      MAX(p.LastActivityDate) OVER (PARTITION BY p.OwnerUserId) AS UserLastActivityOverall
    FROM Posts p
    LEFT JOIN Comments c
      ON p.Id = c.PostId
    LEFT JOIN Votes v
      ON p.Id = v.PostId
    WHERE
      p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY
      p.Id,
      p.OwnerUserId,
      p.PostTypeId,
      p.Score,
      p.CommentCount,
      p.FavoriteCount,
      p.CreationDate,
      p.LastActivityDate
  ),
  UserEngagement AS (
    SELECT
      upi.OwnerUserId,
      COUNT(DISTINCT CASE WHEN upi.PostTypeId = 1 THEN upi.PostId ELSE NULL END) AS QuestionCount,
      COUNT(DISTINCT CASE WHEN upi.PostTypeId = 2 THEN upi.PostId ELSE NULL END) AS AnswerCount,
      AVG(COALESCE(upi.Score, 0)) AS AverageScore,
      SUM(upi.CommentCountForPost) AS TotalCommentsMade,
      SUM(upi.UpVoteCountForPost) AS TotalUpvotesReceived,
      SUM(upi.DownVoteCountForPost) AS TotalDownvotesReceived,
      MAX(upi.PostCreationDate) AS LatestPostDate,
      MIN(upi.PostCreationDate) AS EarliestPostDate,
      MAX(upi.UserLastActivityOverall) AS UserOverallLastActivity
    FROM UserPostInteractions upi
    GROUP BY
      upi.OwnerUserId
  ),
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.Title,
      p.Tags,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.FavoriteCount DESC) AS ScoreRank,
      DENSE_RANK() OVER (ORDER BY p.AnswerCount DESC) AS AnswerCountRank,
      LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousPostScore,
      LEAD(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS NextPostScore,
      SUM(p.Score) OVER (ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningScoreTotal,
      p.CreationDate
    FROM Posts p
    WHERE
      p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
  ),
  PostHistorySummary AS (
    SELECT
      ph.PostId,
      COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 5 THEN ph.Id ELSE NULL END) AS BodyEditCount,
      COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 4 THEN ph.Id ELSE NULL END) AS TitleEditCount,
      MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5)
    GROUP BY
      ph.PostId
  ),
  PostLinkAnalysis AS (
    SELECT
      pl.PostId,
      COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 1 THEN pl.RelatedPostId ELSE NULL END) AS LinkedPostsCount,
      COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId ELSE NULL END) AS DuplicatePostsCount
    FROM PostLinks pl
    GROUP BY
      pl.PostId
  )
SELECT
  rp.PostId,
  rp.Title,
  rp.Tags,
  rp.Score,
  rp.AnswerCount,
  rp.CommentCount,
  rp.FavoriteCount,
  ue.QuestionCount,
  ue.AnswerCount AS UserAnswerCount,
  ue.AverageScore AS UserAverageScore,
  ue.TotalCommentsMade AS UserTotalCommentsMade,
  ue.TotalUpvotesReceived AS UserTotalUpvotesReceived,
  ue.UserOverallLastActivity,
  phs.BodyEditCount,
  phs.TitleEditCount,
  phs.LastEditDate,
  pla.LinkedPostsCount,
  pla.DuplicatePostsCount,
  rp.ScoreRank,
  rp.AnswerCountRank,
  rp.PreviousPostScore,
  rp.NextPostScore,
  rp.RunningScoreTotal,
  CASE
    WHEN rp.Score > 100 AND rp.FavoriteCount > 10 THEN 'Highly Engaged'
    WHEN rp.Score > 20 OR rp.AnswerCount > 5 THEN 'Moderately Engaged'
    ELSE 'Low Engagement'
  END AS EngagementLevel,
  CASE
    WHEN rp.Tags LIKE '%<sql>%' THEN 'SQL Related'
    WHEN rp.Tags LIKE '%<python>%' THEN 'Python Related'
    ELSE 'Other'
  END AS TechnologyCategory,
  CHAR_LENGTH(rp.Title) AS TitleLength,
  SUBSTRING(rp.Title FROM 1 FOR 10) AS TitlePrefix,
  COALESCE(rp.AnswerCount, 0) * COALESCE(rp.FavoriteCount, 0) AS ScoreFavoriteProduct,
  ue.AverageScore - rp.Score AS ScoreVsUserAvgDiff,
  CASE WHEN rp.OwnerUserId IS NULL THEN 'Community' ELSE 'User_' || rp.OwnerUserId END AS OwnerIdentifier,
  rp.RunningScoreTotal / (ue.QuestionCount + ue.AnswerCount + 1) AS AvgScorePerInteraction
FROM RankedPosts rp
JOIN UserEngagement ue
  ON rp.OwnerUserId = ue.OwnerUserId
LEFT JOIN PostHistorySummary phs
  ON rp.PostId = phs.PostId
LEFT JOIN PostLinkAnalysis pla
  ON rp.PostId = pla.PostId
WHERE
  rp.Score > 0
  AND ue.QuestionCount > 5
  AND COALESCE(phs.BodyEditCount, 0) + COALESCE(phs.TitleEditCount, 0) < 10
ORDER BY
  rp.ScoreRank,
  rp.AnswerCountRank;