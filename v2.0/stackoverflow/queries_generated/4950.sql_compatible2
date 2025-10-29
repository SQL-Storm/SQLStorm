WITH
  RankedQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.Title AS QuestionTitle,
      p.OwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.AnswerCount,
      u.DisplayName AS OwnerDisplayName,
      ROW_NUMBER() OVER (
        ORDER BY
          p.Score DESC,
          p.CreationDate DESC
      ) AS Rank,
      COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCountOnQuestion,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 1
        ELSE 0
      END AS IsClosedQuestion,
      p.ClosedDate
    FROM
      Posts AS p
      JOIN Users AS u
        ON p.OwnerUserId = u.Id
      LEFT JOIN Comments AS c
        ON c.PostId = p.Id
    WHERE
      p.PostTypeId = 1
      AND p.CreationDate >= TIMESTAMP '2023-01-01'
  ),
  QuestionAnswers AS (
    SELECT
      p.ParentId AS QuestionId,
      COUNT(p.Id) AS AnswerCountForQuestion,
      SUM(p.Score) AS TotalAnswerScore,
      MAX(p.CreationDate) AS LastAnswerDate
    FROM
      Posts AS p
    WHERE
      p.PostTypeId = 2
      AND p.ParentId IN (
        SELECT
          QuestionId
        FROM
          RankedQuestions
      )
    GROUP BY
      p.ParentId
  ),
  UserPostContributions AS (
    SELECT
      ph.UserId,
      COUNT(DISTINCT ph.PostId) AS DistinctPostsContributedTo,
      SUM(
        CASE
          WHEN ph.PostHistoryTypeId IN (1, 2, 3) THEN 1
          WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 2
          ELSE 0
        END
      ) AS TotalEditsOrCreations
    FROM
      PostHistory AS ph
    WHERE
      ph.UserId IS NOT NULL
      AND ph.UserId <> -1
      AND ph.CreationDate >= TIMESTAMP '2023-01-01'
    GROUP BY
      ph.UserId
  ),
  TopContributors AS (
    SELECT
      Id,
      DisplayName,
      Reputation,
      ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS ReputationRank
    FROM
      Users
    WHERE
      CreationDate <= TIMESTAMP '2022-12-31'
  )
SELECT
  RQ.QuestionId,
  RQ.QuestionTitle,
  RQ.OwnerDisplayName,
  RQ.QuestionScore,
  RQ.AnswerCount AS QuestionAnswerCount,
  QA.AnswerCountForQuestion,
  QA.TotalAnswerScore,
  RQ.CommentCountOnQuestion,
  RQ.IsClosedQuestion,
  CAST(
    EXTRACT(EPOCH FROM (COALESCE(RQ.ClosedDate, TIMESTAMP '2024-10-01 12:34:56') - RQ.QuestionCreationDate)) / 86400
    AS INTEGER
  ) AS DaysToCloseOrActive,
  TC.DisplayName AS TopContributorDisplayName,
  TC.ReputationRank,
  UPC.DistinctPostsContributedTo,
  UPC.TotalEditsOrCreations,
  CASE
    WHEN RQ.OwnerUserId = TC.Id THEN 'Same User'
    ELSE 'Different User'
  END AS OwnerVsTopContributor,
  UPPER(SUBSTR(RQ.QuestionTitle, 1, 3)) AS TitlePrefix,
  (
    SELECT
      COUNT(*)
    FROM
      Votes AS v
    WHERE
      v.PostId = RQ.QuestionId
      AND v.VoteTypeId IN (2, 3)
  ) AS TotalVotesOnQuestion
FROM
  RankedQuestions AS RQ
LEFT JOIN
  QuestionAnswers AS QA
  ON RQ.QuestionId = QA.QuestionId
LEFT JOIN
  UserPostContributions AS UPC
  ON RQ.OwnerUserId = UPC.UserId
LEFT JOIN
  TopContributors AS TC
  ON TC.ReputationRank <= 5
WHERE
  RQ.Rank <= 100
  AND COALESCE(QA.TotalAnswerScore, 0) > 10
  AND RQ.OwnerDisplayName IS NOT NULL
ORDER BY
  RQ.Rank;