-- {"query": "4715.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1010} 

WITH
  UserPostStats AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS TotalPosts,
      SUM(p.Score) AS TotalScore,
      AVG(p.ViewCount) AS AvgViewCount,
      MAX(p.CreationDate) AS LastPostDate
    FROM Posts AS p
    WHERE
      p.OwnerUserId IS NOT NULL
    GROUP BY
      p.OwnerUserId
  ),
  UserCommentStats AS (
    SELECT
      c.UserId,
      COUNT(c.Id) AS TotalComments,
      SUM(c.Score) AS TotalCommentScore
    FROM Comments AS c
    WHERE
      c.UserId IS NOT NULL
    GROUP BY
      c.UserId
  ),
  UserVoteStats AS (
    SELECT
      v.UserId,
      COUNT(CASE WHEN vt.Name = 'UpMod' THEN v.Id END) AS UpvotesGiven,
      COUNT(CASE WHEN vt.Name = 'DownMod' THEN v.Id END) AS DownvotesGiven,
      COUNT(CASE WHEN vt.Name = 'Favorite' THEN v.Id END) AS FavoritesGiven
    FROM Votes AS v
    JOIN VoteTypes AS vt
      ON v.VoteTypeId = vt.Id
    WHERE
      v.UserId IS NOT NULL
    GROUP BY
      v.UserId
  ),
  HighReputationUsers AS (
    SELECT
      u.Id,
      u.DisplayName,
      u.Reputation,
      COALESCE(ups.TotalPosts, 0) AS TotalPosts,
      COALESCE(ucs.TotalComments, 0) AS TotalComments,
      COALESCE(uvs.UpvotesGiven, 0) AS UpvotesGiven,
      COALESCE(uvs.DownvotesGiven, 0) AS DownvotesGiven,
      COALESCE(uvs.FavoritesGiven, 0) AS FavoritesGiven,
      DATEDIFF(
        day,
        u.CreationDate,
        u.LastAccessDate
      ) AS AccountAgeDays,
      CASE
        WHEN ups.LastPostDate IS NOT NULL THEN DATEDIFF(
          day,
          ups.LastPostDate,
          GETDATE()
        )
        ELSE NULL
      END AS DaysSinceLastPost
    FROM Users AS u
    LEFT JOIN UserPostStats AS ups
      ON u.Id = ups.OwnerUserId
    LEFT JOIN UserCommentStats AS ucs
      ON u.Id = ucs.UserId
    LEFT JOIN UserVoteStats AS uvs
      ON u.Id = uvs.UserId
    WHERE
      u.Reputation > 10000
  )
SELECT
  hr.DisplayName,
  hr.Reputation,
  hr.TotalPosts,
  hr.TotalComments,
  hr.UpvotesGiven,
  hr.DownvotesGiven,
  hr.FavoritesGiven,
  hr.AccountAgeDays,
  hr.DaysSinceLastPost,
  (
    SELECT
      COUNT(*)
    FROM Badges AS b
    WHERE
      b.UserId = hr.Id
      AND b.Class = 1 /* Gold Badges */
  ) AS GoldBadges,
  (
    SELECT
      COUNT(*)
    FROM Badges AS b
    WHERE
      b.UserId = hr.Id
      AND b.Class = 2 /* Silver Badges */
  ) AS SilverBadges,
  (
    SELECT
      COUNT(*)
    FROM Badges AS b
    WHERE
      b.UserId = hr.Id
      AND b.Class = 3 /* Bronze Badges */
  ) AS BronzeBadges,
  CASE
    WHEN hr.DaysSinceLastPost IS NOT NULL AND hr.DaysSinceLastPost < 30 THEN 'Active'
    WHEN hr.DaysSinceLastPost IS NOT NULL AND hr.DaysSinceLastPost < 365 THEN 'Moderately Active'
    ELSE 'Inactive'
  END AS ActivityStatus,
  ROW_NUMBER() OVER (ORDER BY hr.Reputation DESC, hr.TotalPosts DESC) AS RankByReputation,
  LAG(hr.Reputation, 1, 0) OVER (ORDER BY hr.Reputation DESC) AS PreviousReputation
FROM HighReputationUsers AS hr
WHERE
  hr.DisplayName IS NOT NULL
  AND hr.AccountAgeDays > 180
  AND hr.TotalPosts > 50
ORDER BY
  RankByReputation;
