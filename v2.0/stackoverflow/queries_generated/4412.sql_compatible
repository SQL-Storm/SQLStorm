WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.PostTypeId,
      p.AcceptedAnswerId,
      p.ParentId,
      p.CreationDate AS PostCreationDate,
      p.Score AS PostScore,
      p.ViewCount AS PostViewCount,
      p.AnswerCount AS PostAnswerCount,
      p.CommentCount AS PostCommentCount,
      p.FavoriteCount AS PostFavoriteCount,
      p.ClosedDate AS PostClosedDate,
      p.CommunityOwnedDate,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RowNumByUser,
      DENSE_RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank,
      LAG(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PreviousPostScore,
      LEAD(p.Score, 1, 0) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS NextPostScore,
      SUM(p.Score) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS TotalScoreForPostType
    FROM Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.OwnerUserId != -1
  ),
  UserPostStats AS (
    SELECT
      rp.OwnerUserId,
      COUNT(rp.PostId) AS TotalPosts,
      AVG(CAST(rp.PostScore AS DECIMAL(10, 2))) AS AvgPostScore,
      MAX(rp.PostScore) AS MaxPostScore,
      SUM(rp.PostViewCount) AS TotalViews,
      SUM(rp.PostAnswerCount) AS TotalAnswers,
      SUM(rp.PostCommentCount) AS TotalComments,
      COUNT(CASE WHEN rp.PostClosedDate IS NOT NULL THEN rp.PostId END) AS ClosedPostCount,
      SUM(CASE WHEN rp.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN rp.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM RankedPosts AS rp
    GROUP BY
      rp.OwnerUserId
  ),
  TopUsers AS (
    SELECT
      ups.OwnerUserId,
      ups.TotalPosts,
      ups.AvgPostScore,
      ups.MaxPostScore,
      ups.TotalViews,
      ups.TotalAnswers,
      ups.TotalComments,
      ups.ClosedPostCount,
      ups.QuestionCount,
      ups.AnswerCount,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      u.LastAccessDate AS UserLastAccessDate,
      u.Views AS UserViewsTotal,
      u.UpVotes AS UserUpVotesTotal,
      u.DownVotes AS UserDownVotesTotal,
      CASE
        WHEN ups.TotalPosts > 1000 THEN 'Prolific'
        WHEN ups.TotalPosts > 100 THEN 'Experienced'
        ELSE 'Newer'
      END AS UserActivityLevel,
      ROW_NUMBER() OVER (ORDER BY ups.TotalPosts DESC, ups.MaxPostScore DESC) AS UserRank
    FROM UserPostStats AS ups
    JOIN Users AS u
      ON ups.OwnerUserId = u.Id
    WHERE
      ups.TotalPosts > 50
  )
SELECT
  u.DisplayName AS UserName,
  u.Reputation,
  u.UserActivityLevel,
  u.UserRank,
  u.UserCreationDate,
  u.UserLastAccessDate,
  u.TotalPosts,
  u.AvgPostScore,
  u.MaxPostScore,
  u.TotalViews,
  u.TotalAnswers,
  u.TotalComments,
  u.ClosedPostCount,
  u.QuestionCount,
  u.AnswerCount,
  (
    SELECT
      COUNT(b.Id)
    FROM Badges AS b
    WHERE
      b.UserId = u.OwnerUserId
      AND b.Class = 1
  ) AS GoldBadgeCount,
  (
    SELECT
      COUNT(b.Id)
    FROM Badges AS b
    WHERE
      b.UserId = u.OwnerUserId
      AND b.Class = 2
  ) AS SilverBadgeCount,
  (
    SELECT
      COUNT(b.Id)
    FROM Badges AS b
    WHERE
      b.UserId = u.OwnerUserId
      AND b.Class = 3
  ) AS BronzeBadgeCount,
  CASE
    WHEN u.UserLastAccessDate < (cast('2024-10-01' as date) - INTERVAL '365 day') THEN 'Inactive'
    ELSE 'Active'
  END AS UserStatus,
  (
    SELECT
      COUNT(DISTINCT ph.PostId)
    FROM PostHistory AS ph
    JOIN Posts AS p
      ON ph.PostId = p.Id
    WHERE
      ph.UserId = u.OwnerUserId
      AND ph.PostHistoryTypeId IN (4, 5, 6)
      AND p.OwnerUserId = u.OwnerUserId
  ) AS EditsMade,
  CASE
    WHEN u.UserUpVotesTotal > u.UserDownVotesTotal * 2 THEN 'PositiveVoter'
    WHEN u.UserDownVotesTotal > u.UserUpVotesTotal * 2 THEN 'NegativeVoter'
    ELSE 'BalancedVoter'
  END AS VotingPattern,
  COALESCE(u.UserViewsTotal, 0) AS UserProfileViews,
  (
    SELECT
      COUNT(c.Id)
    FROM Comments AS c
    WHERE
      c.UserId = u.OwnerUserId
      AND c.Score > 5
  ) AS HighScoreCommentCount,
  (
    SELECT
      STRING_AGG(DISTINCT pt.Name, ', ')
    FROM Posts AS p
    JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.OwnerUserId = u.OwnerUserId
    GROUP BY
      p.OwnerUserId
    ORDER BY
      COUNT(p.Id) DESC
    LIMIT 1
  ) AS MostFrequentPostType,
  CASE
    WHEN u.UserCreationDate BETWEEN (cast('2024-10-01' as date) - INTERVAL '30 day') AND cast('2024-10-01' as date) THEN 'Recent'
    ELSE 'Established'
  END AS UserTenure,
  rp.ScoreRank,
  rp.PreviousPostScore,
  rp.NextPostScore,
  rp.TotalScoreForPostType,
  CASE
    WHEN rp.PostClosedDate IS NOT NULL
    AND rp.PostClosedDate > (cast('2024-10-01' as date) - INTERVAL '7 day') THEN 'RecentlyClosed'
    ELSE 'NotRecentlyClosed'
  END AS RecentClosureStatus
FROM TopUsers AS u
LEFT JOIN RankedPosts AS rp
  ON u.OwnerUserId = rp.OwnerUserId AND rp.RowNumByUser = 1
ORDER BY
  u.UserRank,
  rp.ScoreRank;