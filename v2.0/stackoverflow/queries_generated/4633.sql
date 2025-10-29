-- {"query": "4633.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1404} 

WITH
  RankedUserPosts AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.CreationDate AS PostCreationDate,
      p.Score AS PostScore,
      p.AnswerCount AS PostAnswerCount,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRank,
      SUM(CASE WHEN c.UserId IS NOT NULL THEN 1 ELSE 0 END) AS CommentCountOnPost,
      MAX(c.CreationDate) AS LastCommentDate
    FROM Posts AS p
    LEFT JOIN Comments AS c
      ON p.Id = c.PostId
    WHERE
      p.PostTypeId = 1 -- Questions
    GROUP BY
      p.Id,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      p.AnswerCount
  ),
  UserAggregates AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COUNT(DISTINCT p.Id) AS TotalQuestions,
      SUM(p.PostScore) AS TotalQuestionScore,
      AVG(CAST(p.PostAnswerCount AS NUMERIC)) AS AvgAnswersPerQuestion,
      (
        SELECT
          COUNT(*)
        FROM Badges AS b
        WHERE
          b.UserId = u.Id AND b.Class = 1
      ) AS GoldBadgeCount,
      (
        SELECT
          COUNT(*)
        FROM Badges AS b
        WHERE
          b.UserId = u.Id AND b.Class = 2
      ) AS SilverBadgeCount,
      (
        SELECT
          COUNT(*)
        FROM Badges AS b
        WHERE
          b.UserId = u.Id AND b.Class = 3
      ) AS BronzeBadgeCount,
      MAX(CASE WHEN p.PostRank <= 5 THEN p.PostScore ELSE 0 END) AS Top5PostScore,
      COUNT(CASE WHEN p.LastCommentDate > DATEADD(day, -30, GETDATE()) THEN p.PostId ELSE NULL END) AS RecentCommentsCount,
      CASE WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl <> '' THEN 1 ELSE 0 END AS HasWebsite
    FROM Users AS u
    LEFT JOIN RankedUserPosts AS p
      ON u.Id = p.OwnerUserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      u.WebsiteUrl
  )
SELECT
  ua.DisplayName,
  ua.Reputation,
  ua.UserCreationDate,
  ua.TotalQuestions,
  ua.TotalQuestionScore,
  ua.AvgAnswersPerQuestion,
  ua.GoldBadgeCount,
  ua.SilverBadgeCount,
  ua.BronzeBadgeCount,
  ua.Top5PostScore,
  ua.RecentCommentsCount,
  ua.HasWebsite,
  COUNT(DISTINCT ph.Id) AS PostHistoryCount,
  MAX(ph.CreationDate) AS LastPostHistoryDate,
  CASE
    WHEN MAX(ph.CreationDate) IS NULL THEN 'Never'
    WHEN MAX(ph.CreationDate) > DATEADD(year, -1, GETDATE()) THEN 'Within Last Year'
    WHEN MAX(ph.CreationDate) > DATEADD(year, -5, GETDATE()) THEN 'Within Last 5 Years'
    ELSE 'Older Than 5 Years'
  END AS PostHistoryRecency,
  COALESCE(pht.Name, 'Unknown') AS LastPostHistoryType,
  SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedQuestionCount,
  SUM(CASE WHEN p.FavoriteCount > 100 THEN 1 ELSE 0 END) AS PopularQuestionCount,
  COUNT(DISTINCT pl.RelatedPostId) AS LinkedPostsCount,
  (
    SELECT
      COUNT(DISTINCT v.Id)
    FROM Votes AS v
    WHERE
      v.UserId = ua.UserId AND v.VoteTypeId = 2 -- Upvotes
  ) AS TotalUpvotesGiven,
  (
    SELECT
      SUM(v.BountyAmount)
    FROM Votes AS v
    WHERE
      v.UserId = ua.UserId AND v.VoteTypeId = 8 -- BountyStart
  ) AS TotalBountyAmount,
  CASE WHEN ua.Reputation > 100000 THEN 'High' WHEN ua.Reputation > 10000 THEN 'Medium' ELSE 'Low' END AS ReputationTier,
  CASE WHEN EXISTS (SELECT 1 FROM Comments AS c WHERE c.UserId = ua.UserId AND c.Text LIKE '%great%answer%') THEN 'Yes' ELSE 'No' END AS GaveGreatAnswerComment,
  CASE WHEN ua.DisplayName LIKE '%[^a-zA-Z0-9 ]%' THEN 'Contains Special Chars' ELSE 'Clean' END AS DisplayNameType
FROM UserAggregates AS ua
LEFT JOIN Posts AS p
  ON ua.UserId = p.OwnerUserId
LEFT JOIN PostHistory AS ph
  ON ua.UserId = ph.UserId
LEFT JOIN PostHistoryTypes AS pht
  ON ph.PostHistoryTypeId = pht.Id
LEFT JOIN PostLinks AS pl
  ON p.Id = pl.PostId
WHERE
  ua.TotalQuestions > 0
GROUP BY
  ua.UserId,
  ua.DisplayName,
  ua.Reputation,
  ua.UserCreationDate,
  ua.TotalQuestions,
  ua.TotalQuestionScore,
  ua.AvgAnswersPerQuestion,
  ua.GoldBadgeCount,
  ua.SilverBadgeCount,
  ua.BronzeBadgeCount,
  ua.Top5PostScore,
  ua.RecentCommentsCount,
  ua.HasWebsite,
  pht.Name
HAVING
  COUNT(DISTINCT ph.Id) > 5 OR SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) > 2
ORDER BY
  ua.Reputation DESC,
  ua.TotalQuestions DESC
LIMIT 100;
