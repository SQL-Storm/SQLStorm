WITH
  RankedPosts AS (
    SELECT
      p.Id,
      p.PostTypeId,
      p.OwnerUserId,
      p.Title,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ClosedDate,
      p.CommunityOwnedDate,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank,
      COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCountPerPost
    FROM Posts p
    LEFT JOIN Comments c
      ON p.Id = c.PostId
    WHERE
      p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '365 days'
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      COUNT(DISTINCT p.Id) AS QuestionCount,
      COUNT(DISTINCT a.Id) AS AnswerCount,
      SUM(p.Score) AS TotalQuestionScore,
      SUM(a.Score) AS TotalAnswerScore,
      MAX(u.Reputation) AS MaxReputation,
      AVG(u.Views) AS AvgUserViews
    FROM Users u
    LEFT JOIN Posts p
      ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Posts a
      ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    WHERE
      u.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '730 days'
    GROUP BY
      u.Id
  ),
  PostMetrics AS (
    SELECT
      rp.Id,
      rp.Title,
      rp.PostTypeId,
      rp.OwnerUserId,
      rp.Score,
      rp.ViewCount,
      rp.AnswerCount AS PostAnswerCount,
      rp.CommentCountPerPost,
      rp.FavoriteCount,
      rp.ClosedDate,
      rp.CommunityOwnedDate,
      CASE
        WHEN rp.ClosedDate IS NOT NULL THEN 1
        ELSE 0
      END AS IsClosed,
      CASE
        WHEN rp.CommunityOwnedDate IS NOT NULL THEN 1
        ELSE 0
      END AS IsCommunityOwned,
      ua.QuestionCount AS UserTotalQuestions,
      ua.AnswerCount AS UserTotalAnswers,
      ua.TotalQuestionScore AS UserTotalQScore,
      ua.TotalAnswerScore AS UserTotalAScore,
      ua.MaxReputation AS UserMaxRep,
      ua.AvgUserViews AS UserAvgViews,
      rp.ScoreRank,
      ROW_NUMBER() OVER (ORDER BY rp.Score DESC, rp.ViewCount DESC) AS OverallRank
    FROM RankedPosts rp
    LEFT JOIN UserActivity ua
      ON rp.OwnerUserId = ua.UserId
    WHERE
      rp.PostTypeId IN (1, 2)
  )
SELECT
  pm.Id,
  pm.Title,
  pt.Name AS PostTypeName,
  COALESCE(u.DisplayName, 'Unknown User') AS OwnerDisplayName,
  pm.Score,
  pm.ViewCount,
  pm.PostAnswerCount,
  pm.CommentCountPerPost,
  pm.FavoriteCount,
  pm.IsClosed,
  pm.IsCommunityOwned,
  'User Score: ' || CAST(pm.UserTotalQScore AS VARCHAR) || '/' || CAST(pm.UserTotalAScore AS VARCHAR) AS UserScoreSummary,
  'User Reputation: ' || CAST(pm.UserMaxRep AS VARCHAR) AS UserReputation,
  pm.ScoreRank,
  pm.OverallRank,
  CASE
    WHEN pm.Score > 500 AND pm.ViewCount > 10000 THEN 'High Impact'
    WHEN pm.Score < 0 AND pm.ViewCount < 100 THEN 'Low Engagement'
    ELSE 'Standard'
  END AS PostImpactCategory,
  CASE
    WHEN ua.UserId IS NULL THEN 'New User'
    WHEN ua.QuestionCount = 0 AND ua.AnswerCount = 0 THEN 'Inactive User'
    ELSE 'Active User'
  END AS UserStatus,
  LOWER(SUBSTRING(COALESCE(pm.Title, 'No Title') FROM 1 FOR 5)) AS TitlePrefix,
  COALESCE(ph.CommentCount, 0) AS RecentPostHistoryComments,
  CASE
    WHEN pl.LinkTypeId = 1 THEN 'Linked'
    WHEN pl.LinkTypeId = 3 THEN 'Duplicate'
    ELSE 'Other Link Type'
  END AS PostLinkType
FROM PostMetrics pm
LEFT JOIN PostTypes pt
  ON pm.PostTypeId = pt.Id
LEFT JOIN Users u
  ON pm.OwnerUserId = u.Id
LEFT JOIN (
  SELECT
    PostId,
    COUNT(*) AS CommentCount
  FROM PostHistory
  WHERE
    PostHistoryTypeId = 5 OR PostHistoryTypeId = 10
  GROUP BY
    PostId
) ph
  ON pm.Id = ph.PostId
LEFT JOIN PostLinks pl
  ON pm.Id = pl.PostId AND pl.LinkTypeId IN (1, 3)
LEFT JOIN UserActivity ua
  ON pm.OwnerUserId = ua.UserId
ORDER BY
  pm.OverallRank;