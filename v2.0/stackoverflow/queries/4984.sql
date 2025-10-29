-- {"query": "4984.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1976}
WITH
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      p.Id AS PostId,
      p.PostTypeId,
      p.CreationDate,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ClosedDate,
      pt.Name AS PostTypeName,
      CASE
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        ELSE 'Other'
      END AS SimplifiedPostType,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS UserActivityRank,
      LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore,
      LEAD(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostScore,
      AVG(CAST(p.Score AS DOUBLE PRECISION)) OVER (PARTITION BY p.OwnerUserId) AS AvgUserPostScore,
      SUM(p.ViewCount) OVER (PARTITION BY p.OwnerUserId) AS TotalUserViews,
      COUNT(p.Id) OVER (PARTITION BY p.OwnerUserId) AS TotalUserPosts
    FROM Posts AS p
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0 AND p.CreationDate >= DATE '2023-01-01'
  ),
  PostEngagement AS (
    SELECT
      upa.OwnerUserId,
      upa.PostId,
      upa.PostTypeName,
      upa.SimplifiedPostType,
      upa.Score,
      upa.AnswerCount,
      upa.CommentCount,
      upa.FavoriteCount,
      upa.ClosedDate,
      upa.CreationDate,
      COALESCE(upa.AnswerCount, 0) + COALESCE(upa.CommentCount, 0) AS TotalInteractions,
      CASE
        WHEN upa.ClosedDate IS NOT NULL THEN 1
        ELSE 0
      END AS IsClosed,
      (upa.Score * 1.0 / NULLIF(upa.TotalUserPosts, 0)) AS NormalizedScore,
      CASE
        WHEN upa.FavoriteCount > 0 THEN 'Favorited'
        WHEN upa.AnswerCount > 3 THEN 'Highly Answered'
        WHEN upa.Score > 50 THEN 'High Score'
        ELSE 'Standard'
      END AS PostStatusCategory,
      upa.PreviousPostScore,
      upa.NextPostScore,
      upa.AvgUserPostScore,
      upa.TotalUserViews,
      upa.TotalUserPosts
    FROM UserPostActivity AS upa
    WHERE
      upa.UserActivityRank <= 100
  ),
  UserSummary AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      u.Views AS UserTotalViews,
      u.UpVotes AS UserTotalUpVotes,
      u.DownVotes AS UserTotalDownVotes,
      COUNT(DISTINCT pe.PostId) AS UserPostsCount,
      SUM(pe.Score) AS UserTotalScore,
      AVG(CAST(pe.Score AS DOUBLE PRECISION)) AS UserAvgScore,
      SUM(pe.TotalInteractions) AS UserTotalInteractions,
      MAX(pe.CreationDate) AS UserLastPostDate,
      COUNT(CASE WHEN pe.PostTypeName = 'Question' THEN 1 END) AS UserQuestionCount,
      COUNT(CASE WHEN pe.PostTypeName = 'Answer' THEN 1 END) AS UserAnswerCount,
      COUNT(CASE WHEN pe.IsClosed = 1 THEN 1 END) AS UserClosedPostCount,
      STRING_AGG(DISTINCT pt.Name, ', ') AS UserPostTypeNames
    FROM Users AS u
    LEFT JOIN PostEngagement AS pe
      ON u.Id = pe.OwnerUserId
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    LEFT JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    WHERE
      u.Id IS NOT NULL AND u.Id > 0 AND u.CreationDate >= DATE '2023-01-01'
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      u.Views,
      u.UpVotes,
      u.DownVotes
  )
SELECT
  us.UserId,
  us.DisplayName,
  us.Reputation,
  us.UserCreationDate,
  us.UserTotalViews,
  us.UserTotalUpVotes,
  us.UserTotalDownVotes,
  us.UserPostsCount,
  us.UserTotalScore,
  us.UserAvgScore,
  us.UserTotalInteractions,
  us.UserLastPostDate,
  us.UserQuestionCount,
  us.UserAnswerCount,
  us.UserClosedPostCount,
  us.UserPostTypeNames,
  COUNT(DISTINCT pe.PostId) AS UserTopPosts,
  SUM(pe.NormalizedScore) AS SumNormalizedScore,
  AVG(CAST(pe.TotalInteractions AS DOUBLE PRECISION)) AS AvgPostInteractions,
  MAX(pe.Score) AS MaxPostScore,
  MIN(pe.Score) AS MinPostScore,
  COUNT(CASE WHEN pe.PostStatusCategory = 'Favorited' THEN 1 END) AS FavoritedPosts,
  COUNT(CASE WHEN pe.PostStatusCategory = 'Highly Answered' THEN 1 END) AS HighlyAnsweredPosts,
  COUNT(CASE WHEN pe.PostStatusCategory = 'High Score' THEN 1 END) AS HighScorePosts,
  CASE
    WHEN us.UserAvgScore > 100 AND us.UserPostsCount > 500 THEN 'High Performer'
    WHEN us.UserAvgScore > 50 AND us.UserPostsCount > 100 THEN 'Medium Performer'
    ELSE 'Standard Performer'
  END AS PerformanceTier,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM Badges AS b
      WHERE
        b.UserId = us.UserId AND b.Name LIKE '%Greatest Answer%'
    ) THEN 'Has Greatest Answer Badge'
    ELSE 'No Greatest Answer Badge'
  END AS BadgeStatus,
  (
    SELECT
      COUNT(*)
    FROM Votes AS v
    WHERE
      v.UserId = us.UserId AND v.VoteTypeId = 2 AND v.CreationDate >= (us.UserLastPostDate - INTERVAL '30' DAY)
  ) AS RecentUpvotesGiven,
  (
    SELECT
      COUNT(*)
    FROM PostHistory AS ph
    WHERE
      ph.UserId = us.UserId AND ph.PostHistoryTypeId IN (4, 5) AND ph.CreationDate >= (us.UserCreationDate - INTERVAL '365' DAY)
  ) AS RecentEdits,
  (
    SELECT
      COUNT(c.Id)
    FROM Comments AS c
    WHERE
      c.UserId = us.UserId AND c.CreationDate >= (us.UserLastPostDate - INTERVAL '90' DAY)
  ) AS RecentCommentsCount,
  (
    SELECT
      SUM(CASE WHEN pe2.SimplifiedPostType = 'Question' THEN 1 ELSE 0 END)
    FROM PostEngagement AS pe2
    WHERE
      pe2.OwnerUserId = us.UserId
  ) AS TotalQuestionsByThisUser
FROM UserSummary AS us
LEFT JOIN PostEngagement AS pe
  ON us.UserId = pe.OwnerUserId
GROUP BY
  us.UserId,
  us.DisplayName,
  us.Reputation,
  us.UserCreationDate,
  us.UserTotalViews,
  us.UserTotalUpVotes,
  us.UserTotalDownVotes,
  us.UserPostsCount,
  us.UserTotalScore,
  us.UserAvgScore,
  us.UserTotalInteractions,
  us.UserLastPostDate,
  us.UserQuestionCount,
  us.UserAnswerCount,
  us.UserClosedPostCount,
  us.UserPostTypeNames
HAVING
  us.UserPostsCount > 10
ORDER BY
  us.Reputation DESC,
  us.UserTotalScore DESC
LIMIT 1000;