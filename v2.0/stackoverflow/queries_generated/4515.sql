-- {"query": "4515.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1802} 

WITH
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      p.PostTypeId,
      p.Id AS PostId,
      p.CreationDate AS PostCreationDate,
      p.Score AS PostScore,
      p.CommentCount,
      p.FavoriteCount,
      p.ViewCount,
      pt.Name AS PostTypeName,
      CASE
        WHEN pt.Id = 1 THEN p.Title
        WHEN pt.Id = 2 THEN SUBSTRING(p.Body, 1, 50)
        ELSE 'N/A'
      END AS PostTitleOrExcerpt,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM
      Posts AS p
      JOIN PostTypes AS pt
        ON p.PostTypeId = pt.Id
    WHERE
      p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
  ),
  UserCommentActivity AS (
    SELECT
      c.UserId,
      c.PostId,
      c.Score AS CommentScore,
      c.CreationDate AS CommentCreationDate,
      ROW_NUMBER() OVER (PARTITION BY c.UserId ORDER BY c.CreationDate DESC) AS rn
    FROM
      Comments AS c
    WHERE
      c.UserId IS NOT NULL
  ),
  UserVoteActivity AS (
    SELECT
      v.UserId,
      v.PostId,
      vt.Name AS VoteTypeName,
      v.CreationDate AS VoteCreationDate,
      ROW_NUMBER() OVER (PARTITION BY v.UserId ORDER BY v.CreationDate DESC) AS rn
    FROM
      Votes AS v
      JOIN VoteTypes AS vt
        ON v.VoteTypeId = vt.Id
    WHERE
      v.UserId IS NOT NULL
  ),
  UserReputationChanges AS (
    SELECT
      u.Id AS UserId,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      MAX(upa.PostCreationDate) AS LastPostDate,
      MAX(uca.CommentCreationDate) AS LastCommentDate,
      MAX(uva.VoteCreationDate) AS LastVoteDate,
      COUNT(DISTINCT upa.PostId) AS TotalPosts,
      SUM(CASE WHEN upa.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
      SUM(CASE WHEN upa.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
      AVG(upa.PostScore) AS AvgPostScore,
      SUM(upa.CommentCount) AS TotalCommentsOnPosts,
      SUM(upa.FavoriteCount) AS TotalFavoritesOnPosts,
      SUM(upa.ViewCount) AS TotalViewsOnPosts,
      COUNT(DISTINCT uca.PostId) AS PostsCommentedOn,
      SUM(uca.CommentScore) AS TotalCommentScore,
      COUNT(DISTINCT uva.PostId) AS PostsVotedOn,
      COUNT(CASE WHEN uva.VoteTypeName = 'UpMod' THEN 1 ELSE NULL END) AS TotalUpVotes,
      COUNT(CASE WHEN uva.VoteTypeName = 'DownMod' THEN 1 ELSE NULL END) AS TotalDownVotes,
      COUNT(CASE WHEN uva.VoteTypeName = 'Favorite' THEN 1 ELSE NULL END) AS TotalFavorites,
      COUNT(CASE WHEN uva.VoteTypeName = 'AcceptedByOriginator' THEN 1 ELSE NULL END) AS TotalAcceptedAnswers,
      SUM(CASE WHEN uva.VoteTypeName = 'DownMod' THEN 1 ELSE NULL END) * 1.0 / NULLIF(COUNT(uva.PostId), 0) AS DownvoteRatio
    FROM
      Users AS u
      LEFT JOIN UserPostActivity AS upa
        ON u.Id = upa.OwnerUserId
      LEFT JOIN UserCommentActivity AS uca
        ON u.Id = uca.UserId
      LEFT JOIN UserVoteActivity AS uva
        ON u.Id = uva.UserId
    GROUP BY
      u.Id,
      u.Reputation,
      u.CreationDate
  )
SELECT
  ura.UserId,
  ura.Reputation,
  ura.UserCreationDate,
  ura.LastPostDate,
  ura.LastCommentDate,
  ura.LastVoteDate,
  ura.TotalPosts,
  ura.TotalQuestions,
  ura.TotalAnswers,
  ura.AvgPostScore,
  ura.TotalCommentsOnPosts,
  ura.TotalFavoritesOnPosts,
  ura.TotalViewsOnPosts,
  ura.PostsCommentedOn,
  ura.TotalCommentScore,
  ura.PostsVotedOn,
  ura.TotalUpVotes,
  ura.TotalDownVotes,
  ura.TotalFavorites,
  ura.DownvoteRatio,
  (
    SELECT
      COUNT(*)
    FROM
      Badges AS b
    WHERE
      b.UserId = ura.UserId AND b.Class = 1
  ) AS GoldBadges,
  (
    SELECT
      COUNT(*)
    FROM
      Badges AS b
    WHERE
      b.UserId = ura.UserId AND b.Class = 2
  ) AS SilverBadges,
  (
    SELECT
      COUNT(*)
    FROM
      Badges AS b
    WHERE
      b.UserId = ura.UserId AND b.Class = 3
  ) AS BronzeBadges,
  CASE
    WHEN ura.Reputation > 100000 THEN 'Legendary'
    WHEN ura.Reputation > 50000 THEN 'Expert'
    WHEN ura.Reputation > 10000 THEN 'Advanced'
    WHEN ura.Reputation > 1000 THEN 'Intermediate'
    WHEN ura.Reputation > 100 THEN 'Novice'
    ELSE 'Beginner'
  END AS ReputationLevel,
  CASE
    WHEN ura.TotalPosts = 0 THEN 'No Posts'
    WHEN ura.AvgPostScore > 50 THEN 'Highly Valued'
    WHEN ura.AvgPostScore > 10 THEN 'Moderately Valued'
    ELSE 'Standard'
  END AS ContentValue,
  UPPER(COALESCE(u.DisplayName, 'Anonymous')) AS DisplayNameUpper,
  COALESCE(u.Location, 'Unknown Location') AS UserLocation,
  CASE
    WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl <> '' THEN 'Has Website'
    ELSE 'No Website'
  END AS HasWebsite,
  CASE
    WHEN u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 100 THEN 'Detailed Bio'
    WHEN u.AboutMe IS NOT NULL THEN 'Brief Bio'
    ELSE 'No Bio'
  END AS BioStatus,
  DATE_PART('year', AGE(CURRENT_TIMESTAMP, u.CreationDate)) AS UserAgeInYears,
  DATE_PART('day', AGE(u.LastAccessDate, u.CreationDate)) AS DaysSinceFirstAccess,
  CASE
    WHEN ura.DownvoteRatio IS NULL THEN 0.0
    ELSE ROUND(ura.DownvoteRatio * 100, 2)
  END AS DownvotePercentage
FROM
  UserReputationChanges AS ura
  JOIN Users AS u
    ON ura.UserId = u.Id
WHERE
  (ura.TotalPosts > 0 OR ura.TotalQuestions > 0 OR ura.TotalAnswers > 0)
  AND (ura.AvgPostScore IS NOT NULL OR ura.TotalCommentScore > 0)
  AND ura.UserCreationDate >= '2010-01-01'
  AND ura.Reputation BETWEEN 1000 AND 50000
  AND ura.DownvoteRatio IS NULL OR ura.DownvoteRatio < 0.1
ORDER BY
  ura.Reputation DESC,
  ura.TotalPosts DESC
LIMIT 100;
