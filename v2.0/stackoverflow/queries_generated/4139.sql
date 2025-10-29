-- {"query": "4139.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2420} 

WITH
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS PostCount,
      SUM(p.Score) AS TotalScore,
      SUM(p.ViewCount) AS TotalViews,
      AVG(p.AnswerCount) AS AvgAnswerCount,
      MAX(p.CreationDate) AS LatestPostDate
    FROM
      Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  UserCommentActivity AS (
    SELECT
      c.UserId,
      COUNT(c.Id) AS CommentCount,
      SUM(c.Score) AS TotalCommentScore,
      MAX(c.CreationDate) AS LatestCommentDate
    FROM
      Comments AS c
    WHERE
      c.UserId IS NOT NULL
    GROUP BY
      c.UserId
  ),
  UserVoteActivity AS (
    SELECT
      v.UserId,
      COUNT(v.Id) AS VoteCount,
      SUM(
        CASE
          WHEN vt.Name = 'UpMod' THEN 1
          ELSE 0
        END
      ) AS UpVoteCount,
      SUM(
        CASE
          WHEN vt.Name = 'DownMod' THEN 1
          ELSE 0
        END
      ) AS DownVoteCount,
      MAX(v.CreationDate) AS LatestVoteDate
    FROM
      Votes AS v
      JOIN VoteTypes AS vt ON v.VoteTypeId = vt.Id
    WHERE
      v.UserId IS NOT NULL
    GROUP BY
      v.UserId
  ),
  UserBadgeEarned AS (
    SELECT
      b.UserId,
      COUNT(b.Id) AS BadgeCount,
      SUM(
        CASE
          WHEN b.Class = 1 THEN 1
          ELSE 0
        END
      ) AS GoldBadgeCount,
      SUM(
        CASE
          WHEN b.Class = 2 THEN 1
          ELSE 0
        END
      ) AS SilverBadgeCount,
      SUM(
        CASE
          WHEN b.Class = 3 THEN 1
          ELSE 0
        END
      ) AS BronzeBadgeCount,
      MAX(b.Date) AS LatestBadgeDate
    FROM
      Badges AS b
    GROUP BY
      b.UserId
  ),
  UserReputationChange AS (
    SELECT
      u.Id AS UserId,
      u.Reputation,
      u.UpVotes,
      u.DownVotes,
      u.Views AS ProfileViews,
      u.CreationDate AS UserCreationDate,
      u.LastAccessDate AS UserLastAccessDate,
      COALESCE(upa.PostCount, 0) AS TotalPosts,
      COALESCE(upa.TotalScore, 0) AS TotalPostScore,
      COALESCE(upa.TotalViews, 0) AS TotalPostViews,
      COALESCE(uca.CommentCount, 0) AS TotalComments,
      COALESCE(uca.TotalCommentScore, 0) AS TotalCommentScore,
      COALESCE(uva.VoteCount, 0) AS TotalVotesCast,
      COALESCE(uva.UpVoteCount, 0) AS TotalUpVotesCast,
      COALESCE(uva.DownVoteCount, 0) AS TotalDownVotesCast,
      COALESCE(ube.BadgeCount, 0) AS TotalBadgesEarned,
      COALESCE(ube.GoldBadgeCount, 0) AS TotalGoldBadges,
      COALESCE(ube.SilverBadgeCount, 0) AS TotalSilverBadges,
      COALESCE(ube.BronzeBadgeCount, 0) AS TotalBronzeBadges,
      CASE
        WHEN u.WebsiteUrl IS NOT NULL THEN 1
        ELSE 0
      END AS HasWebsite,
      CASE
        WHEN u.Location IS NOT NULL THEN 1
        ELSE 0
      END AS HasLocation,
      CASE
        WHEN u.AboutMe IS NOT NULL THEN LENGTH(u.AboutMe)
        ELSE 0
      END AS AboutMeLength,
      (
        CAST(
          STRFTIME('%J', u.LastAccessDate) AS REAL
        ) - CAST(
          STRFTIME('%J', u.CreationDate) AS REAL
        )
      ) AS DaysActive,
      (
        CAST(
          STRFTIME('%J', u.LastAccessDate) AS REAL
        ) - CAST(
          STRFTIME('%J', COALESCE(upa.LatestPostDate, u.CreationDate)) AS REAL
        )
      ) AS DaysSinceLastPost,
      (
        CAST(
          STRFTIME('%J', u.LastAccessDate) AS REAL
        ) - CAST(
          STRFTIME('%J', COALESCE(uca.LatestCommentDate, u.CreationDate)) AS REAL
        )
      ) AS DaysSinceLastComment,
      (
        CAST(
          STRFTIME('%J', u.LastAccessDate) AS REAL
        ) - CAST(
          STRFTIME('%J', COALESCE(uva.LatestVoteDate, u.CreationDate)) AS REAL
        )
      ) AS DaysSinceLastVote,
      (
        CAST(
          STRFTIME('%J', u.LastAccessDate) AS REAL
        ) - CAST(
          STRFTIME('%J', COALESCE(ube.LatestBadgeDate, u.CreationDate)) AS REAL
        )
      ) AS DaysSinceLastBadge
    FROM
      Users AS u
      LEFT JOIN UserPostActivity AS upa ON u.Id = upa.OwnerUserId
      LEFT JOIN UserCommentActivity AS uca ON u.Id = uca.UserId
      LEFT JOIN UserVoteActivity AS uva ON u.Id = uva.UserId
      LEFT JOIN UserBadgeEarned AS ube ON u.Id = ube.UserId
  )
SELECT
  rc.UserId,
  rc.Reputation,
  rc.UpVotes AS UserUpVotes,
  rc.DownVotes AS UserDownVotes,
  rc.ProfileViews,
  rc.UserCreationDate,
  rc.UserLastAccessDate,
  rc.TotalPosts,
  rc.TotalPostScore,
  rc.TotalPostViews,
  rc.TotalComments,
  rc.TotalCommentScore,
  rc.TotalVotesCast,
  rc.TotalUpVotesCast,
  rc.TotalDownVotesCast,
  rc.TotalBadgesEarned,
  rc.TotalGoldBadges,
  rc.TotalSilverBadges,
  rc.TotalBronzeBadges,
  rc.HasWebsite,
  rc.HasLocation,
  rc.AboutMeLength,
  rc.DaysActive,
  rc.DaysSinceLastPost,
  rc.DaysSinceLastComment,
  rc.DaysSinceLastVote,
  rc.DaysSinceLastBadge,
  COALESCE(p_q.QuestionCount, 0) AS QuestionCount,
  COALESCE(p_a.AnswerCount, 0) AS AnswerCount,
  COALESCE(p_w.WikiCount, 0) AS WikiCount,
  COALESCE(p_c.ClosedCount, 0) AS ClosedCount,
  COALESCE(p_l.LinkCount, 0) AS LinkCount,
  CASE
    WHEN rc.TotalPostScore > 1000 AND rc.TotalComments > 50 THEN 'Highly Active Contributor'
    WHEN rc.TotalPostScore > 500 AND rc.TotalComments > 20 THEN 'Active Contributor'
    WHEN rc.TotalPostScore > 100 THEN 'Moderately Active Contributor'
    ELSE 'Lesser Active Contributor'
  END AS ContributorTier,
  SUBSTRING(rc.UserDisplayName, 1, 3) AS FirstThreeCharsOfName,
  CASE
    WHEN rc.UserLastAccessDate < DATE('now', '-1 year') THEN 'Inactive'
    ELSE 'Active'
  END AS ActivityStatus,
  COALESCE(
    (
      SELECT
        AVG(Score)
      FROM
        Posts AS sub_p
      WHERE
        sub_p.OwnerUserId = rc.UserId
          AND sub_p.PostTypeId = 1
    ),
    0
  ) AS AvgQuestionScore,
  (
    SELECT
      COUNT(*)
    FROM
      PostHistory AS ph
    WHERE
      ph.UserId = rc.UserId
      AND ph.PostHistoryTypeId IN (4, 5, 6)
  ) AS EditHistoryCount,
  (
    SELECT
      SUM(CASE WHEN vt.Name = 'Favorite' THEN 1 ELSE 0 END)
    FROM
      Votes AS v
      JOIN VoteTypes AS vt ON v.VoteTypeId = vt.Id
    WHERE
      v.UserId = rc.UserId
  ) AS FavoriteCount,
  COALESCE(
    (
      SELECT
        COUNT(DISTINCT pl.RelatedPostId)
      FROM
        PostLinks AS pl
      WHERE
        pl.PostId = rc.UserId
          AND pl.LinkTypeId = 3
    ),
    0
  ) AS DuplicateLinkCount
FROM
  UserReputationChange AS rc
  LEFT JOIN (
    SELECT
      OwnerUserId,
      COUNT(Id) AS QuestionCount
    FROM
      Posts
    WHERE
      PostTypeId = 1
    GROUP BY
      OwnerUserId
  ) AS p_q ON rc.UserId = p_q.OwnerUserId
  LEFT JOIN (
    SELECT
      OwnerUserId,
      COUNT(Id) AS AnswerCount
    FROM
      Posts
    WHERE
      PostTypeId = 2
    GROUP BY
      OwnerUserId
  ) AS p_a ON rc.UserId = p_a.OwnerUserId
  LEFT JOIN (
    SELECT
      OwnerUserId,
      COUNT(Id) AS WikiCount
    FROM
      Posts
    WHERE
      PostTypeId IN (3, 5)
    GROUP BY
      OwnerUserId
  ) AS p_w ON rc.UserId = p_w.OwnerUserId
  LEFT JOIN (
    SELECT
      OwnerUserId,
      COUNT(Id) AS ClosedCount
    FROM
      Posts
    WHERE
      ClosedDate IS NOT NULL
    GROUP BY
      OwnerUserId
  ) AS p_c ON rc.UserId = p_c.OwnerUserId
  LEFT JOIN (
    SELECT
      PostId,
      COUNT(Id) AS LinkCount
    FROM
      PostLinks
    GROUP BY
      PostId
  ) AS p_l ON rc.UserId = p_l.PostId;
