-- {"query": "4809.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1609} 
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
      Posts AS p
    JOIN
      PostTypes AS pt
      ON p.PostTypeId = pt.Id
    LEFT JOIN
      Comments AS c
      ON p.OwnerUserId = c.UserId
    LEFT JOIN
      Votes AS v
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
      CASE WHEN t.IsModeratorOnly = 1 THEN 'Moderator Only' ELSE 'Public' END AS TagAccess
    FROM
      Tags AS t
    LEFT JOIN
      Posts AS p
      ON LOWER(t.TagName) = LOWER(SUBSTRING(p.Tags, 2, CHARINDEX('>', p.Tags) - 2)) OR LOWER(t.TagName) = LOWER(SUBSTRING(p.Tags, CHARINDEX('>', REVERSE(p.Tags)) + 1, LEN(p.Tags) - CHARINDEX('>', REVERSE(p.Tags)) - 1)) OR (CHARINDEX('><', p.Tags) > 0 AND LOWER(t.TagName) = LOWER(SUBSTRING(p.Tags, CHARINDEX('><', p.Tags) + 2, LEN(p.Tags) - CHARINDEX('><', p.Tags) - 3)))
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
      Badges AS b
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
      Posts AS p
    JOIN
      Votes AS v
      ON p.Id = v.PostId
    WHERE
      p.CreationDate > DATEADD(year, -1, GETDATE())
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
  DATEDIFF(day, u.CreationDate, GETDATE()) AS AccountAgeInDays,
  CASE WHEN u.WebsiteUrl IS NULL THEN 'No Website' ELSE 'Has Website' END AS WebsiteStatus,
  COALESCE(up.AverageScore, 0) AS AverageUserScore,
  DATEDIFF(day, ubs.LastBadgeAwarded, GETDATE()) AS DaysSinceLastBadge
FROM
  Users AS u
LEFT JOIN
  UserPostEngagement AS up
  ON u.Id = up.OwnerUserId
LEFT JOIN
  UserBadgeSummary AS ubs
  ON u.Id = ubs.UserId
LEFT JOIN
  PostVoteAnalysis AS pva
  ON u.Id = pva.OwnerUserId
LEFT JOIN
  Tags AS t
  ON LOWER(t.TagName) = LOWER(u.DisplayName) -- A tenuous join for demonstration
LEFT JOIN
  TagWisdom AS tw
  ON t.TagName = tw.TagName
WHERE
  u.Id IN (SELECT UserId FROM Votes WHERE VoteTypeId = 16) -- Users who approved an edit
  AND COALESCE(up.TotalPosts, 0) > 10
  AND COALESCE(ubs.GoldBadges, 0) >= 1
ORDER BY
  u.Reputation DESC,
  AccountAgeInDays DESC
OFFSET 100 ROWS FETCH NEXT 50 ROWS ONLY;