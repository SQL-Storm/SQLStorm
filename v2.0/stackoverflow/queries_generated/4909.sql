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
    FROM Posts AS p
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
    FROM Posts AS p
    JOIN Tags AS t
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
      ROW_NUMBER() OVER (ORDER BY TotalQuestionsForTag DESC) AS Rank
    FROM TagActivity
    WHERE
      LastQuestionDateForTag >= DATE('now', '-30 day')
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
        WHEN u.LastAccessDate < DATE('now', '-1 year') THEN 'Inactive'
        WHEN u.LastAccessDate >= DATE('now', '-30 day') THEN 'Active'
        ELSE 'Moderately Active'
      END AS ActivityStatus
    FROM Users AS u
    LEFT JOIN UserPostStats AS ups
      ON u.Id = ups.OwnerUserId
    LEFT JOIN (
      SELECT
        PostId,
        COUNT(Id) AS CommentCount
      FROM Comments
      GROUP BY
        PostId
    ) AS c
      ON u.Id = (
        SELECT
          OwnerUserId
        FROM Posts
        WHERE
          Id = c.PostId
      )
  )
SELECT
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
  SUBSTR(ua.DisplayName, 1, INSTR(ua.DisplayName, ' ') - 1) AS FirstName,
  CASE
    WHEN ups.AnswerCount > ups.QuestionCount * 2 THEN 'Answer-Focused'
    WHEN ups.QuestionCount > ups.AnswerCount * 2 THEN 'Question-Focused'
    ELSE 'Balanced'
  END AS UserFocus,
  (
    SELECT
      COUNT(*)
    FROM Badges AS b
    WHERE
      b.UserId = ua.UserId AND b.Class = 1
  ) AS GoldBadgeCount,
  (
    SELECT
      COUNT(*)
    FROM Badges AS b
    WHERE
      b.UserId = ua.UserId AND b.Class = 2
  ) AS SilverBadgeCount,
  (
    SELECT
      COUNT(*)
    FROM Badges AS b
    WHERE
      b.UserId = ua.UserId AND b.Class = 3
  ) AS BronzeBadgeCount,
  CASE
    WHEN ua.CreationDate < DATE('now', '-5 year') THEN 'Long-Term'
    WHEN ua.CreationDate >= DATE('now', '-1 year') THEN 'New'
    ELSE 'Mid-Term'
  END AS Tenure,
  SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY ua.UserId) AS DuplicateLinkCount
FROM UserActivity AS ua
LEFT JOIN UserPostStats AS ups
  ON ua.UserId = ups.OwnerUserId
LEFT JOIN HotTags AS ht
  ON ht.Rank = 1
LEFT JOIN PostLinks AS pl
  ON ua.UserId = (
    SELECT
      OwnerUserId
    FROM Posts
    WHERE
      Id = pl.PostId
  )
WHERE
  ua.Reputation > 1000
  AND ua.CreationDate < DATE('now', '-180 day')
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
  ua.CreationDate
HAVING
  COUNT(pl.Id) > 0 OR ua.Reputation > 10000;
