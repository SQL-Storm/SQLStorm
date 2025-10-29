WITH
  RankedUserVotes AS (
    SELECT
      UserId,
      VoteTypeId,
      COUNT(Id) AS VoteCount,
      ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY COUNT(Id) DESC) AS VoteRank
    FROM Votes
    WHERE
      UserId IS NOT NULL
      AND VoteTypeId IN (2, 3)
    GROUP BY
      UserId,
      VoteTypeId
  ),
  UserPostScores AS (
    SELECT
      p.OwnerUserId,
      SUM(p.Score) AS TotalPostScore,
      AVG(p.Score) AS AveragePostScore,
      MAX(p.Score) AS MaxPostScore,
      COUNT(p.Id) AS NumberOfPosts
    FROM Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.PostTypeId IN (1, 2)
      AND p.Score IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  UserCommentStats AS (
    SELECT
      c.UserId,
      COUNT(c.Id) AS TotalComments,
      AVG(c.Score) AS AverageCommentScore,
      SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveCommentCount
    FROM Comments AS c
    WHERE
      c.UserId IS NOT NULL
      AND c.Score IS NOT NULL
    GROUP BY
      c.UserId
  ),
  UserPostHistory AS (
    SELECT
      ph.UserId,
      COUNT(ph.Id) AS TotalPostHistoryEntries,
      SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditsMade,
      SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 14, 19) THEN 1 ELSE 0 END) AS ModerationActions
    FROM PostHistory AS ph
    WHERE
      ph.UserId IS NOT NULL
    GROUP BY
      ph.UserId
  ),
  UserBadgeCounts AS (
    SELECT
      b.UserId,
      SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
      SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
      SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
      SUM(CASE WHEN b.TagBased = TRUE THEN 1 ELSE 0 END) AS TagBadges
    FROM Badges AS b
    GROUP BY
      b.UserId
  ),
  TopUsers AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      u.Views,
      u.UpVotes AS UserUpVotes,
      u.DownVotes AS UserDownVotes,
      COALESCE(ups.VoteCount, 0) AS TotalUpvotes,
      COALESCE(dws.VoteCount, 0) AS TotalDownvotes,
      COALESCE(ups_rank.VoteRank, 0) AS UpvoteRank,
      COALESCE(dws_rank.VoteRank, 0) AS DownvoteRank,
      COALESCE(ups.VoteCount, 0) - COALESCE(dws.VoteCount, 0) AS NetVotes,
      COALESCE(ups.VoteCount, 0) + COALESCE(dws.VoteCount, 0) AS TotalVotesCast,
      COALESCE(pu.TotalPostScore, 0) AS TotalScoreFromPosts,
      COALESCE(pu.AveragePostScore, 0.0) AS AvgScorePerPost,
      COALESCE(pu.MaxPostScore, 0) AS MaxScoreOfAPost,
      COALESCE(pu.NumberOfPosts, 0) AS TotalPostsAuthored,
      COALESCE(uc.TotalComments, 0) AS TotalCommentsAuthored,
      COALESCE(uc.AverageCommentScore, 0.0) AS AvgScorePerComment,
      COALESCE(uc.PositiveCommentCount, 0) AS PositiveComments,
      COALESCE(uph.TotalPostHistoryEntries, 0) AS TotalHistoryEntries,
      COALESCE(uph.EditsMade, 0) AS TotalEdits,
      COALESCE(uph.ModerationActions, 0) AS TotalModerationActions,
      COALESCE(ubc.GoldBadges, 0) AS GoldBadgeCount,
      COALESCE(ubc.SilverBadges, 0) AS SilverBadgeCount,
      COALESCE(ubc.BronzeBadges, 0) AS BronzeBadgeCount,
      COALESCE(ubc.TagBadges, 0) AS TagBadgeCount,
      CASE
        WHEN u.WebsiteUrl IS NOT NULL AND COALESCE(uph.TotalPostHistoryEntries, 0) > 100 THEN 'Active and has external presence'
        WHEN u.Location IS NOT NULL AND COALESCE(pu.NumberOfPosts, 0) > 1000 THEN 'Experienced contributor'
        WHEN u.AboutMe IS NULL THEN 'Profile incomplete'
        ELSE 'Standard profile'
      END AS ProfileStatus,
      CASE
        WHEN u.LastAccessDate < (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1' YEAR) THEN 'Inactive'
        WHEN u.LastAccessDate < (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '3' MONTH) THEN 'Recently Inactive'
        ELSE 'Active'
      END AS UserActivity,
      COALESCE(ps.TagName, 'General') AS FavoriteTag,
      COALESCE(ps.Count, 0) AS FavoriteTagCount
    FROM Users AS u
    LEFT JOIN RankedUserVotes AS ups
      ON u.Id = ups.UserId
      AND ups.VoteTypeId = 2
    LEFT JOIN RankedUserVotes AS dws
      ON u.Id = dws.UserId
      AND dws.VoteTypeId = 3
    LEFT JOIN RankedUserVotes AS ups_rank
      ON u.Id = ups_rank.UserId
      AND ups_rank.VoteTypeId = 2
      AND ups_rank.VoteRank = 1
    LEFT JOIN RankedUserVotes AS dws_rank
      ON u.Id = dws_rank.UserId
      AND dws_rank.VoteTypeId = 3
      AND dws_rank.VoteRank = 1
    LEFT JOIN UserPostScores AS pu
      ON u.Id = pu.OwnerUserId
    LEFT JOIN UserCommentStats AS uc
      ON u.Id = uc.UserId
    LEFT JOIN UserPostHistory AS uph
      ON u.Id = uph.UserId
    LEFT JOIN UserBadgeCounts AS ubc
      ON u.Id = ubc.UserId
    LEFT JOIN (
      SELECT
        t.TagName,
        t.Count,
        p.OwnerUserId
      FROM Tags AS t
      JOIN Posts AS p
        ON t.Id = p.Id
      WHERE
        p.OwnerUserId IS NOT NULL
    ) AS ps
      ON u.Id = ps.OwnerUserId
    WHERE
      u.Reputation > 1000
      AND COALESCE(pu.NumberOfPosts, 0) > 10
  )
SELECT
  td.DisplayName,
  td.Reputation,
  td.UserActivity,
  td.TotalPostsAuthored,
  td.TotalScoreFromPosts,
  td.AvgScorePerPost,
  td.TotalCommentsAuthored,
  td.AvgScorePerComment,
  td.TotalEdits,
  td.TotalModerationActions,
  td.GoldBadgeCount,
  td.SilverBadgeCount,
  td.BronzeBadgeCount,
  td.FavoriteTag,
  CASE
    WHEN td.NetVotes > 10000 THEN 'Highly Valued'
    WHEN td.NetVotes BETWEEN 1000 AND 10000 THEN 'Valued Contributor'
    WHEN td.NetVotes BETWEEN 100 AND 999 THEN 'Moderately Valued'
    ELSE 'Standard Contributor'
  END AS VoteValueCategory,
  CASE
    WHEN td.ProfileStatus = 'Active and has external presence' AND td.UserActivity = 'Active' THEN 'Highly Engaged User'
    WHEN td.ProfileStatus = 'Experienced contributor' AND td.UserActivity = 'Active' THEN 'Established Expert'
    WHEN td.ProfileStatus = 'Profile incomplete' AND td.UserActivity = 'Active' THEN 'Needs Profile Enhancement'
    ELSE 'Typical User Profile'
  END AS UserEngagementTier,
  (
    SELECT
      COUNT(*)
    FROM Posts AS p_inner
    WHERE
      p_inner.OwnerUserId = td.UserId
      AND p_inner.ClosedDate IS NOT NULL
  ) AS TotalClosedPostsAuthored,
  (
    SELECT
      COUNT(*)
    FROM Comments AS c_inner
    WHERE
      c_inner.UserId = td.UserId
      AND c_inner.Score < 0
  ) AS TotalNegativeScoreComments,
  (td.DisplayName || ' (' || td.Reputation || ')') AS DisplayNameWithReputation,
  CASE
    WHEN td.AvgScorePerPost > 50 THEN 'High Average Post Score'
    WHEN td.AvgScorePerPost > 10 THEN 'Medium Average Post Score'
    ELSE 'Low Average Post Score'
  END AS PostScorePerformance,
  CASE
    WHEN td.TotalEdits > 100 AND td.TotalModerationActions > 10 THEN 'Highly Active Editor & Moderator'
    WHEN td.TotalEdits > 50 THEN 'Active Editor'
    WHEN td.TotalModerationActions > 5 THEN 'Active Moderator'
    ELSE 'Standard Activity Level'
  END AS ActivityProfile
FROM TopUsers AS td
WHERE
  td.TotalPostsAuthored > 50
  AND td.Reputation > 5000
ORDER BY
  td.Reputation DESC,
  td.TotalScoreFromPosts DESC;