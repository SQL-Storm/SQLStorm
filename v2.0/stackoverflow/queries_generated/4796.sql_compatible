WITH
  RecentQuestions AS (
    SELECT
      Id,
      OwnerUserId,
      Title,
      Tags,
      AnswerCount,
      FavoriteCount,
      CAST(
        COALESCE(FavoriteCount, 0) AS FLOAT
      ) / NULLIF(CASE WHEN AnswerCount = 0 THEN 1 ELSE AnswerCount END, 0) AS FavoriteAnswerRatio,
      CreationDate
    FROM Posts
    WHERE
      PostTypeId = 1
      AND CreationDate > (cast('2024-10-01' as date) - INTERVAL '30 days')
      AND AnswerCount IS NOT NULL
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(DISTINCT ph.Id) AS PostHistoryCount,
      MAX(ph.CreationDate) AS LastPostHistoryDate,
      SUM(
        CASE
          WHEN ph.PostHistoryTypeId IN (2, 5) THEN 1
          ELSE 0
        END
      ) AS BodyEdits,
      u.CreationDate
    FROM Users AS u
    LEFT JOIN PostHistory AS ph
      ON u.Id = ph.UserId
    WHERE
      u.CreationDate > (cast('2024-10-01' as date) - INTERVAL '90 days')
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate
  ),
  TagPerformance AS (
    SELECT
      t.TagName,
      COUNT(DISTINCT p.Id) AS QuestionsWithTag,
      AVG(rq.FavoriteAnswerRatio) AS AvgFavoriteAnswerRatio
    FROM Tags AS t
    INNER JOIN Posts AS p
      ON t.Id = (
        SELECT
          Id
        FROM Tags
        WHERE
          TagName = SUBSTRING(p.Tags FROM 2 FOR (POSITION('>' IN p.Tags) - 2))
        LIMIT 1
      )
    LEFT JOIN RecentQuestions AS rq
      ON p.Id = rq.Id
    WHERE
      p.PostTypeId = 1
    GROUP BY
      t.TagName
    HAVING
      COUNT(DISTINCT p.Id) > 10
  )
SELECT
  rq.Title,
  rq.Tags,
  ua.DisplayName AS OwnerDisplayName,
  ua.Reputation,
  ua.PostHistoryCount,
  ua.BodyEdits,
  tp.TagName,
  tp.QuestionsWithTag,
  tp.AvgFavoriteAnswerRatio,
  rq.FavoriteAnswerRatio AS CurrentQuestionFavAnswerRatio,
  COALESCE(
    (
      SELECT
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)
      FROM Votes AS v
      WHERE
        v.PostId = rq.Id AND v.VoteTypeId = 2
    ),
    0
  ) AS UpVoteCount,
  COALESCE(
    (
      SELECT
        COUNT(DISTINCT c.Id)
      FROM Comments AS c
      WHERE
        c.PostId = rq.Id AND c.CreationDate > (cast('2024-10-01' as date) - INTERVAL '7 days')
    ),
    0
  ) AS RecentCommentCount,
  CASE
    WHEN rq.AnswerCount > 50 THEN 'High Answer Count'
    WHEN rq.FavoriteAnswerRatio > 0.5 THEN 'Highly Favorited Per Answer'
    ELSE 'Standard'
  END AS QuestionCategory,
  rq.CreationDate
FROM RecentQuestions AS rq
LEFT JOIN UserActivity AS ua
  ON rq.OwnerUserId = ua.UserId
LEFT JOIN TagPerformance AS tp
  ON tp.TagName = SUBSTRING(rq.Tags FROM 2 FOR (POSITION('>' IN rq.Tags) - 2))
WHERE
  ua.Reputation > 1000
ORDER BY
  rq.CreationDate DESC
LIMIT 100;