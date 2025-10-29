WITH
  HighActivityQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.Title,
      p.OwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.ViewCount AS QuestionViewCount,
      p.AnswerCount,
      p.FavoriteCount,
      COUNT(ph.Id) AS PostHistoryCount,
      ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS rn_score_view
    FROM Posts AS p
    JOIN PostHistoryTypes AS pht
      ON p.PostTypeId = 1 -- Questions only
    LEFT JOIN PostHistory AS ph
      ON p.Id = ph.PostId
    WHERE
      p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '365 days' -- Last year
      AND p.Score > 100
      AND p.ViewCount > 10000
    GROUP BY
      p.Id,
      p.Title,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.FavoriteCount
    HAVING
      COUNT(ph.Id) > 50
  ),
  TopAnswers AS (
    SELECT
      p.Id AS AnswerId,
      p.ParentId AS QuestionId,
      p.OwnerUserId,
      p.CreationDate AS AnswerCreationDate,
      p.Score AS AnswerScore,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn_answer_score
    FROM Posts AS p
    WHERE
      p.PostTypeId = 2 -- Answers only
      AND p.ParentId IN (SELECT QuestionId FROM HighActivityQuestions)
  ),
  UserReputation AS (
    SELECT
      u.Id AS UserId,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COUNT(b.Id) AS BadgeCount,
      SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
      SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount,
      SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgeCount,
      u.Location
    FROM Users AS u
    LEFT JOIN Badges AS b
      ON u.Id = b.UserId
    GROUP BY
      u.Id,
      u.Reputation,
      u.CreationDate,
      u.Location
  ),
  QuestionEngagement AS (
    SELECT
      haq.QuestionId,
      COUNT(DISTINCT c.Id) AS CommentCount,
      COUNT(DISTINCT v.Id) AS VoteCount,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteVoteCount
    FROM HighActivityQuestions AS haq
    LEFT JOIN Comments AS c
      ON haq.QuestionId = c.PostId
    LEFT JOIN Votes AS v
      ON haq.QuestionId = v.PostId
    GROUP BY
      haq.QuestionId
  )
SELECT
  haq.Title AS QuestionTitle,
  haq.QuestionCreationDate,
  haq.QuestionScore,
  haq.QuestionViewCount,
  haq.AnswerCount,
  haq.FavoriteCount,
  haq.PostHistoryCount,
  ur.Reputation AS OwnerReputation,
  ur.BadgeCount,
  ur.GoldBadgeCount,
  ur.SilverBadgeCount,
  ur.BronzeBadgeCount,
  ta.AnswerScore AS TopAnswerScore,
  ta.AnswerCreationDate AS TopAnswerCreationDate,
  qe.CommentCount AS TotalCommentsOnQuestion,
  qe.VoteCount AS TotalVotesOnQuestion,
  qe.UpVoteCount,
  qe.DownVoteCount,
  qe.FavoriteVoteCount,
  CASE
    WHEN haq.QuestionScore > 1000 AND haq.AnswerCount > 20 THEN 'Highly Valued'
    WHEN haq.QuestionScore > 500 OR haq.QuestionViewCount > 50000 THEN 'Popular'
    WHEN haq.PostHistoryCount > 100 THEN 'Active History'
    ELSE 'Standard'
  END AS QuestionCategory,
  UPPER(SUBSTRING(haq.Title FROM 1 FOR 3)) AS TitlePrefix,
  EXTRACT(DOW FROM haq.QuestionCreationDate) AS DayOfWeek,
  CASE
    WHEN ur.Reputation IS NULL THEN 'Unknown'
    WHEN ur.Reputation < 1000 THEN 'Novice'
    WHEN ur.Reputation < 10000 THEN 'Experienced'
    ELSE 'Expert'
  END AS OwnerReputationLevel,
  COALESCE(ur.Location, 'Not Specified') AS OwnerLocation,
  CASE
    WHEN EXISTS (SELECT 1 FROM PostLinks AS pl WHERE pl.PostId = haq.QuestionId AND pl.LinkTypeId = 3) THEN 'Is Duplicate'
    ELSE 'Not Duplicate'
  END AS DuplicateStatus
FROM HighActivityQuestions AS haq
JOIN UserReputation AS ur
  ON haq.OwnerUserId = ur.UserId
LEFT JOIN TopAnswers AS ta
  ON haq.QuestionId = ta.QuestionId AND ta.rn_answer_score = 1
JOIN QuestionEngagement AS qe
  ON haq.QuestionId = qe.QuestionId
WHERE
  haq.rn_score_view <= 100
  AND ta.AnswerScore IS NOT NULL
  AND LEFT(haq.Title, 5) <> '*****' -- Exclude potentially sensitive titles
ORDER BY
  haq.QuestionScore DESC,
  haq.QuestionViewCount DESC
LIMIT 50;