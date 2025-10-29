WITH
  UserPostEngagement AS (
    SELECT
      p.OwnerUserId,
      COUNT(DISTINCT p.Id) AS TotalPosts,
      COUNT(DISTINCT CASE WHEN pt.Name = 'Question' THEN p.Id END) AS Questions,
      COUNT(DISTINCT CASE WHEN pt.Name = 'Answer' THEN p.Id END) AS Answers,
      SUM(CASE WHEN c.Id IS NOT NULL THEN 1 ELSE 0 END) AS CommentsMade,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
      AVG(p.Score) AS AverageScore
    FROM
      Posts p
    JOIN
      PostTypes pt
      ON p.PostTypeId = pt.Id
    LEFT JOIN
      Comments c
      ON p.OwnerUserId = c.UserId
    LEFT JOIN
      Votes v
      ON p.OwnerUserId = v.UserId
    WHERE
      p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY
      p.OwnerUserId
  ),
  TagWisdom AS (
    SELECT
      t.TagName,
      COUNT(DISTINCT p.Id) AS TagPostCount,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TagQuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TagAnswerCount,
      AVG(p.Score) AS AvgTagScore,
      MAX(t.Count) AS MaxTagUsage,
      CASE WHEN t.IsModeratorOnly = TRUE THEN 'Moderator Only' ELSE 'Public' END AS TagAccess
    FROM
      Tags t
    LEFT JOIN
      Posts p
      ON LOWER(t.TagName) = LOWER(SUBSTRING(p.Tags FROM 2 FOR (POSITION('>' IN p.Tags) - 2)))
         OR LOWER(t.TagName) = LOWER(SUBSTRING(p.Tags FROM (LENGTH(p.Tags) - POSITION('>' IN REVERSE(p.Tags)) + 2) FOR (POSITION('>' IN REVERSE(p.Tags)) - 1)))
         OR (POSITION('><' IN p.Tags) > 0 AND LOWER(t.TagName) = LOWER(SUBSTRING(p.Tags FROM (POSITION('><' IN p.Tags) + 2) FOR (LENGTH(p.Tags) - POSITION('><' IN p.Tags) - 3))))
    WHERE
      t.TagName IS NOT NULL
    GROUP BY
      t.TagName,
      t.IsModeratorOnly
    HAVING
      COUNT(DISTINCT p.Id) > 100
  ),
  UserBadgeSummary AS (
    SELECT
      b.UserId,
      COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
      COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
      COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
      MAX(b.Date) AS LastBadgeAwarded
    FROM
      Badges b
    GROUP BY
      b.UserId
  ),
  PostVoteAnalysis AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS Upvotes,
      COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS Downvotes,
      SUM(CASE WHEN v.VoteTypeId IN (2, 3) THEN 1 ELSE 0 END) AS TotalVoteCount,
      CASE
        WHEN COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) > COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) THEN 'Net Positive'
        WHEN COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) < COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) THEN 'Net Negative'
        ELSE 'Neutral'
      END AS VoteSentiment
    FROM
      Posts p
    JOIN
      Votes v
      ON p.Id = v.PostId
    WHERE
      p.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
    GROUP BY
      p.Id,
      p.OwnerUserId
    HAVING
      COUNT(CASE WHEN v.VoteTypeId IN (2, 3) THEN 1 END) > 5
  )
SELECT
  u.DisplayName,
  COALESCE(up.TotalPosts, 0) AS TotalPosts,
  COALESCE(up.Questions, 0) AS Questions,
  COALESCE(up.Answers, 0) AS Answers,
  COALESCE(up.CommentsMade, 0) AS CommentsMade,
  COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
  COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
  COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
  t.TagName,
  COALESCE(tw.TagPostCount, 0) AS TagPostCount,
  tw.TagAccess,
  pva.Upvotes AS PostUpvotes,
  pva.Downvotes AS PostDownvotes,
  pva.VoteSentiment,
  CASE
    WHEN u.Reputation > 100000 THEN 'High Reputation'
    WHEN u.Reputation BETWEEN 10000 AND 100000 THEN 'Medium Reputation'
    ELSE 'Low Reputation'
  END AS ReputationLevel,
  EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - u.CreationDate)) / 86400 AS AccountAgeInDays,
  CASE WHEN u.WebsiteUrl IS NULL THEN 'No Website' ELSE 'Has Website' END AS WebsiteStatus,
  COALESCE(up.AverageScore, 0) AS AverageUserScore,
  EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - ubs.LastBadgeAwarded)) / 86400 AS DaysSinceLastBadge
FROM
  Users u
LEFT JOIN
  UserPostEngagement up
  ON u.Id = up.OwnerUserId
LEFT JOIN
  UserBadgeSummary ubs
  ON u.Id = ubs.UserId
LEFT JOIN
  PostVoteAnalysis pva
  ON u.Id = pva.OwnerUserId
LEFT JOIN
  Tags t
  ON LOWER(t.TagName) = LOWER(u.DisplayName)
LEFT JOIN
  TagWisdom tw
  ON t.TagName = tw.TagName
WHERE
  u.Id IN (SELECT UserId FROM Votes WHERE VoteTypeId = 16)
  AND COALESCE(up.TotalPosts, 0) > 10
  AND COALESCE(ubs.GoldBadges, 0) >= 1
ORDER BY
  u.Reputation DESC,
  AccountAgeInDays DESC
OFFSET 100 ROWS FETCH NEXT 50 ROWS ONLY;