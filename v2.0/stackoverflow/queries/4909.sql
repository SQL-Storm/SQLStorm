-- {"query": "4909.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1320}
WITH
  UserPostStats AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS TotalPosts,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(p.Score) AS AvgScore,
      MAX(p.CreationDate) AS LastPostDate
    FROM Posts p
    WHERE
      p.OwnerUserId IS NOT NULL
      AND p.OwnerUserId <> -1
    GROUP BY
      p.OwnerUserId
  ),
  TagActivity AS (
    SELECT
      t.TagName,
      SUM(p.AnswerCount) AS TotalAnswersForTag,
      SUM(p.FavoriteCount) AS TotalFavoritesForTag,
      COUNT(DISTINCT p.Id) AS TotalQuestionsForTag,
      AVG(p.Score) AS AvgQuestionScoreForTag,
      MAX(p.CreationDate) AS LastQuestionDateForTag
    FROM Posts p
    JOIN Tags t
      ON ',' || p.Tags || ',' LIKE '%,' || t.TagName || ',%'
    WHERE
      p.PostTypeId = 1
      AND p.Tags IS NOT NULL
    GROUP BY
      t.TagName
  ),
  HotTags AS (
    SELECT
      TagName,
      TotalQuestionsForTag,
      ROW_NUMBER() OVER (ORDER BY TotalQuestionsForTag DESC) AS Rank,
      LastQuestionDateForTag
    FROM TagActivity
    WHERE
      LastQuestionDateForTag >= (CAST('2024-10-01' AS date) - INTERVAL '30' DAY)
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      u.Views,
      u.UpVotes,
      u.DownVotes,
      COALESCE(COALESCE(ups.TotalPosts, 0) + COALESCE(c.CommentCount, 0), 0) AS TotalContributions,
      CASE
        WHEN u.LastAccessDate < (CAST('2024-10-01' AS date) - INTERVAL '1' YEAR) THEN 'Inactive'
        WHEN u.LastAccessDate >= (CAST('2024-10-01' AS date) - INTERVAL '30' DAY) THEN 'Active'
        ELSE 'Moderately Active'
      END AS ActivityStatus,
      u.LastAccessDate
    FROM Users u
    LEFT JOIN UserPostStats ups
      ON u.Id = ups.OwnerUserId
    LEFT JOIN (
      SELECT
        PostId,
        COUNT(Id) AS CommentCount
      FROM Comments
      GROUP BY
        PostId
    ) c
      ON u.Id = (
        SELECT
          OwnerUserId
        FROM Posts
        WHERE
          Id = c.PostId
        LIMIT 1
      )
  )
SELECT
  ua.UserId,
  ua.DisplayName,
  ua.Reputation,
  ua.ActivityStatus,
  ups.QuestionCount,
  ups.AnswerCount,
  ups.AvgScore,
  ht.TagName AS TopHotTag,
  COALESCE(ua.Views, 0) AS TotalViews,
  COALESCE(ua.UpVotes, 0) AS TotalUpVotes,
  CASE
    WHEN ua.TotalContributions > 10000 THEN 'Expert'
    WHEN ua.TotalContributions > 1000 THEN 'Advanced'
    ELSE 'Novice'
  END AS ContributionLevel,
  LENGTH(ua.DisplayName) * ua.Reputation AS WeightedDisplayNameLength,
  SUBSTR(ua.DisplayName, 1, (CASE WHEN POSITION(' ' IN ua.DisplayName) > 0 THEN POSITION(' ' IN ua.DisplayName) - 1 ELSE LENGTH(ua.DisplayName) END)) AS FirstName,
  CASE
    WHEN ups.AnswerCount > COALESCE(ups.QuestionCount,0) * 2 THEN 'Answer-Focused'
    WHEN COALESCE(ups.QuestionCount,0) > ups.AnswerCount * 2 THEN 'Question-Focused'
    ELSE 'Balanced'
  END AS UserFocus,
  (
    SELECT
      COUNT(*)
    FROM Badges b
    WHERE
      b.UserId = ua.UserId AND b.Class = 1
  ) AS GoldBadgeCount,
  (
    SELECT
      COUNT(*)
    FROM Badges b
    WHERE
      b.UserId = ua.UserId AND b.Class = 2
  ) AS SilverBadgeCount,
  (
    SELECT
      COUNT(*)
    FROM Badges b
    WHERE
      b.UserId = ua.UserId AND b.Class = 3
  ) AS BronzeBadgeCount,
  CASE
    WHEN ua.CreationDate < (CAST('2024-10-01' AS date) - INTERVAL '5' YEAR) THEN 'Long-Term'
    WHEN ua.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '1' YEAR) THEN 'New'
    ELSE 'Mid-Term'
  END AS Tenure,
  SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateLinkCount,
  COUNT(pl.Id) AS PostLinkCount
FROM UserActivity ua
LEFT JOIN UserPostStats ups
  ON ua.UserId = ups.OwnerUserId
LEFT JOIN HotTags ht
  ON ht.Rank = 1
LEFT JOIN PostLinks pl
  ON ua.UserId = (
    SELECT
      OwnerUserId
    FROM Posts
    WHERE
      Id = pl.PostId
    LIMIT 1
  )
WHERE
  ua.Reputation > 1000
  AND ua.CreationDate < (CAST('2024-10-01' AS date) - INTERVAL '180' DAY)
GROUP BY
  ua.UserId,
  ua.DisplayName,
  ua.Reputation,
  ua.ActivityStatus,
  ups.QuestionCount,
  ups.AnswerCount,
  ups.AvgScore,
  ht.TagName,
  ua.Views,
  ua.UpVotes,
  ua.TotalContributions,
  ua.CreationDate,
  ua.LastAccessDate,
  ua.DownVotes
HAVING
  COUNT(pl.Id) > 0 OR ua.Reputation > 10000;