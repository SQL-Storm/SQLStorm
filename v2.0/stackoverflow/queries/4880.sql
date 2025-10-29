-- {"query": "4880.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1213}
WITH
  RankedUserBadges AS (
    SELECT
      b.UserId,
      b.Name AS BadgeName,
      b.Date AS BadgeDate,
      b.Class AS BadgeClass,
      ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS rn
    FROM Badges b
    WHERE b.Class IN (1, 2)
  ),
  UserPostActivity AS (
    SELECT
      p.OwnerUserId,
      COUNT(p.Id) AS PostCount,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(p.Score) AS AverageScore,
      MAX(p.CreationDate) AS LastPostDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
      AND p.OwnerUserId > 0
    GROUP BY p.OwnerUserId
  ),
  UserCommentStats AS (
    SELECT
      c.UserId,
      COUNT(c.Id) AS CommentCount,
      AVG(c.Score) AS AverageCommentScore
    FROM Comments c
    WHERE c.UserId IS NOT NULL
      AND c.UserId > 0
    GROUP BY c.UserId
  ),
  RecentQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.OwnerUserId,
      p.Title AS QuestionTitle,
      p.CreationDate AS QuestionDate,
      p.AnswerCount,
      p.FavoriteCount,
      ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS QuestionRank
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= (CAST('2024-10-01' AS date) - INTERVAL '30' DAY)
  ),
  TopAnswers AS (
    SELECT
      p.ParentId AS QuestionId,
      p.Id AS AnswerId,
      p.OwnerUserId AS AnswerOwnerUserId,
      p.Score AS AnswerScore,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS AnswerRank
    FROM Posts p
    WHERE p.PostTypeId = 2
      AND p.ParentId IS NOT NULL
  )
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  COALESCE(rub.BadgeName, 'No Top Badges') AS TopBadgeName,
  COALESCE(upa.PostCount, 0) AS TotalPosts,
  COALESCE(upa.QuestionCount, 0) AS TotalQuestions,
  COALESCE(upa.AnswerCount, 0) AS TotalAnswers,
  COALESCE(upa.AverageScore, 0.0) AS AvgPostScore,
  COALESCE(ucs.CommentCount, 0) AS TotalComments,
  COALESCE(ucs.AverageCommentScore, 0.0) AS AvgCommentScore,
  rq.QuestionTitle AS MostRecentQuestionTitle,
  ta.AnswerId AS BestAnswerToMostRecentQuestion,
  CASE
    WHEN u.WebsiteUrl IS NULL OR u.WebsiteUrl = '' THEN 'No Website'
    WHEN LENGTH(u.WebsiteUrl) > 50 THEN SUBSTRING(u.WebsiteUrl FROM 1 FOR 50) || '...'
    ELSE u.WebsiteUrl
  END AS FormattedWebsiteUrl,
  CASE
    WHEN u.AboutMe IS NULL OR u.AboutMe = '' THEN 'User has not provided an introduction.'
    WHEN LENGTH(u.AboutMe) > 100 THEN SUBSTRING(u.AboutMe FROM 1 FOR 100) || '...'
    ELSE u.AboutMe
  END AS ShortenedAboutMe,
  (
    SELECT COUNT(ph.Id)
    FROM PostHistory ph
    WHERE ph.UserId = u.Id
      AND ph.PostHistoryTypeId IN (4, 5, 6)
  ) AS EditCount,
  COALESCE(
    (
      SELECT COUNT(pl.Id)
      FROM PostLinks pl
      WHERE pl.PostId = rq.QuestionId
        AND pl.LinkTypeId = 3
    ),
    0
  ) AS DuplicateLinksToRecentQuestion,
  upa.LastPostDate
FROM Users u
LEFT JOIN RankedUserBadges rub
  ON u.Id = rub.UserId AND rub.rn = 1
LEFT JOIN UserPostActivity upa
  ON u.Id = upa.OwnerUserId
LEFT JOIN UserCommentStats ucs
  ON u.Id = ucs.UserId
LEFT JOIN RecentQuestions rq
  ON u.Id = rq.OwnerUserId
LEFT JOIN TopAnswers ta
  ON rq.QuestionId = ta.QuestionId AND ta.AnswerRank = 1
WHERE u.Reputation > 1000
  AND u.CreationDate < (CAST('2024-10-01' AS date) - INTERVAL '1' YEAR)
  AND (upa.PostCount IS NULL OR upa.PostCount < 500)
GROUP BY
  u.Id,
  u.DisplayName,
  u.Reputation,
  rub.BadgeName,
  upa.PostCount,
  upa.QuestionCount,
  upa.AnswerCount,
  upa.AverageScore,
  ucs.CommentCount,
  ucs.AverageCommentScore,
  rq.QuestionTitle,
  ta.AnswerId,
  u.WebsiteUrl,
  u.AboutMe,
  upa.LastPostDate,
  u.CreationDate,
  rq.QuestionId
ORDER BY
  u.Reputation DESC,
  upa.LastPostDate ASC
LIMIT 100;