WITH
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS PostCount,
      SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS AnswerCount,
      SUM(p.Score) AS TotalScore,
      AVG(p.Score) AS AverageScore,
      MAX(p.CreationDate) AS LatestPostDate
    FROM Posts p
    JOIN PostTypes pt
      ON p.PostTypeId = pt.Id
    WHERE
      p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY
      p.OwnerUserId
  ),
  UserCommentActivity AS (
    SELECT
      c.UserId,
      COUNT(c.Id) AS CommentCount,
      AVG(c.Score) AS AverageCommentScore,
      MAX(c.CreationDate) AS LatestCommentDate
    FROM Comments c
    WHERE
      c.UserId IS NOT NULL AND c.UserId > 0
    GROUP BY
      c.UserId
  ),
  UserVoteActivity AS (
    SELECT
      v.UserId,
      SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVoteCount,
      COUNT(v.Id) AS TotalVoteCount
    FROM Votes v
    JOIN VoteTypes vt
      ON v.VoteTypeId = vt.Id
    WHERE
      v.UserId IS NOT NULL AND v.UserId > 0
    GROUP BY
      v.UserId
  ),
  UserBadgeDistribution AS (
    SELECT
      b.UserId,
      COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadgeCount,
      COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadgeCount,
      COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadgeCount,
      MAX(b.Date) AS LatestBadgeDate
    FROM Badges b
    GROUP BY
      b.UserId
  ),
  PostActivitySummary AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.Title,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.Score,
      p.ViewCount,
      p.ClosedDate,
      DENSE_RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RowNumByUser,
      LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore,
      LEAD(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostScore,
      p.CreationDate AS PostCreationDate
    FROM Posts p
    WHERE
      p.PostTypeId = 1
  ),
  UserAggregatedData AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COALESCE(upa.PostCount, 0) AS TotalPosts,
      COALESCE(upa.QuestionCount, 0) AS TotalQuestions,
      COALESCE(upa.AnswerCount, 0) AS TotalAnswers,
      COALESCE(upa.TotalScore, 0) AS TotalPostScore,
      COALESCE(upa.AverageScore, 0.0) AS AveragePostScore,
      COALESCE(uca.CommentCount, 0) AS TotalComments,
      COALESCE(uca.AverageCommentScore, 0.0) AS AverageCommentScore,
      COALESCE(uva.UpVoteCount, 0) AS TotalUpVotes,
      COALESCE(uva.DownVoteCount, 0) AS TotalDownVotes,
      COALESCE(ubd.GoldBadgeCount, 0) AS GoldBadges,
      COALESCE(ubd.SilverBadgeCount, 0) AS SilverBadges,
      COALESCE(ubd.BronzeBadgeCount, 0) AS BronzeBadges,
      CASE
        WHEN u.Views > 10000 THEN 'High'
        WHEN u.Views > 1000 THEN 'Medium'
        ELSE 'Low'
      END AS ViewCategory,
      CASE
        WHEN COALESCE(upa.AnswerCount, 0) > 0 THEN CAST(COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL AND p.AcceptedAnswerId = p.Id THEN p.Id ELSE NULL END) AS NUMERIC) / NULLIF(upa.AnswerCount,0)
        ELSE 0.0
      END AS AcceptedAnswerRatio,
      EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - u.LastAccessDate)) / 86400.0 AS DaysSinceLastAccess
    FROM Users u
    LEFT JOIN UserPostActivity upa
      ON u.Id = upa.OwnerUserId
    LEFT JOIN UserCommentActivity uca
      ON u.Id = uca.UserId
    LEFT JOIN UserVoteActivity uva
      ON u.Id = uva.UserId
    LEFT JOIN UserBadgeDistribution ubd
      ON u.Id = ubd.UserId
    LEFT JOIN Posts p
      ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      upa.PostCount,
      upa.QuestionCount,
      upa.AnswerCount,
      upa.TotalScore,
      upa.AverageScore,
      uca.CommentCount,
      uca.AverageCommentScore,
      uva.UpVoteCount,
      uva.DownVoteCount,
      ubd.GoldBadgeCount,
      ubd.SilverBadgeCount,
      ubd.BronzeBadgeCount,
      u.Views,
      u.LastAccessDate
  )
SELECT
  pas.PostId,
  pas.Title,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation AS OwnerReputation,
  COALESCE(upa.PostCount,0) AS OwnerTotalPosts,
  COALESCE(upa.QuestionCount,0) AS OwnerTotalQuestions,
  COALESCE(upa.AnswerCount,0) AS OwnerTotalAnswers,
  COALESCE(uca.CommentCount,0) AS OwnerTotalComments,
  COALESCE(ubd.GoldBadgeCount,0) AS OwnerGoldBadges,
  COALESCE(ubd.SilverBadgeCount,0) AS OwnerSilverBadges,
  COALESCE(ubd.BronzeBadgeCount,0) AS OwnerBronzeBadges,
  pas.Score AS PostScore,
  pas.ViewCount AS PostViewCount,
  pas.AnswerCount AS PostAnswerCount,
  pas.CommentCount AS PostCommentCount,
  pas.FavoriteCount AS PostFavoriteCount,
  CASE
    WHEN pas.ClosedDate IS NOT NULL THEN 'Closed'
    ELSE 'Open'
  END AS PostStatus,
  pas.ScoreRank,
  pas.RowNumByUser,
  pas.PreviousPostScore,
  pas.NextPostScore,
  CASE
    WHEN pas.PreviousPostScore > 0 THEN CAST((pas.Score - pas.PreviousPostScore) AS NUMERIC) / pas.PreviousPostScore * 100.0
    ELSE NULL
  END AS ScorePercentageChange,
  CASE
    WHEN EXISTS (
      SELECT 1
      FROM PostLinks pl
      WHERE pl.PostId = pas.PostId AND pl.LinkTypeId = 3
    ) THEN 'Yes'
    ELSE 'No'
  END AS HasDuplicateLink,
  (
    SELECT u2.DisplayName
    FROM Users u2
    WHERE u2.Id = (
      SELECT p2.OwnerUserId
      FROM Posts p2
      ORDER BY p2.Score DESC
      LIMIT 1
    )
  ) AS HighestScoringPostOwner,
  (
    SELECT AVG(Score)
    FROM Posts ans
    WHERE ans.ParentId = pas.PostId AND ans.PostTypeId = 2
  ) AS AverageAnswerScore,
  (
    SELECT
      (CASE WHEN Tags IS NULL OR Tags = '' THEN 0
            ELSE (LENGTH(Tags) - LENGTH(REPLACE(Tags, '><', ''))) / LENGTH('><') + 1 END)
    FROM Posts
    WHERE Id = pas.PostId
  ) AS TagCount,
  (u.DisplayName || ' (' || COALESCE(upa.PostCount,0) || ' posts, ' || CASE WHEN u.Views > 10000 THEN 'High' WHEN u.Views > 1000 THEN 'Medium' ELSE 'Low' END || ' views)') AS UserSummary,
  CASE
    WHEN COALESCE(ubd.GoldBadgeCount,0) > COALESCE(ubd.SilverBadgeCount,0) THEN 'More Gold'
    WHEN COALESCE(ubd.SilverBadgeCount,0) > COALESCE(ubd.GoldBadgeCount,0) THEN 'More Silver'
    ELSE 'Equal or None'
  END AS BadgeBalance,
  CASE
    WHEN (EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - pas.PostCreationDate)) / 86400.0) <= 30 AND u.Reputation > 1000 THEN 'Recent High Rep User Post'
    ELSE 'Other'
  END AS PostRecencyAndReputation
FROM PostActivitySummary pas
JOIN Users u
  ON pas.OwnerUserId = u.Id
LEFT JOIN UserPostActivity upa
  ON u.Id = upa.OwnerUserId
LEFT JOIN UserCommentActivity uca
  ON u.Id = uca.UserId
LEFT JOIN UserBadgeDistribution ubd
  ON u.Id = ubd.UserId
WHERE
  pas.RowNumByUser <= 5
ORDER BY
  pas.Score DESC,
  pas.PostId;