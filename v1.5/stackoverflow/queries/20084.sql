WITH QuestionTags AS (
  SELECT
    p.Id AS QuestionId,
    p.OwnerUserId AS QuestionOwnerId,
    p.AcceptedAnswerId,
    unnest(
      string_to_array(
        substring(p.Tags, 2, length(p.Tags) - 2),
        '><'
      )
    ) AS TagName
  FROM Posts p
  WHERE
    p.PostTypeId = 1 -- Questions
    AND p.CreationDate BETWEEN '2020-01-01' AND '2022-12-31'
    AND p.Tags IS NOT NULL
    AND p.AnswerCount > 2
), UserContributions AS (
  SELECT
    a.OwnerUserId AS UserId,
    qt.TagName,
    a.Id AS AnswerId,
    a.Score AS AnswerScore,
    a.CreationDate AS AnswerCreationDate,
    (CASE WHEN a.Id = qt.AcceptedAnswerId THEN 1 ELSE 0 END) AS IsAcceptedAnswer,
    LENGTH(a.Body) - LENGTH(REPLACE(a.Body, '<p>', '')) AS ParagraphCount
  FROM Posts a
  JOIN QuestionTags qt
    ON a.ParentId = qt.QuestionId
  WHERE
    a.PostTypeId = 2 -- Answers
    AND a.OwnerUserId IS NOT NULL
), TagUserStats AS (
  SELECT
    uc.UserId,
    uc.TagName,
    COUNT(uc.AnswerId) AS TotalAnswers,
    SUM(uc.AnswerScore) AS TotalScore,
    AVG(uc.AnswerScore) AS AvgScore,
    SUM(uc.IsAcceptedAnswer) AS AcceptedAnswers,
    MAX(uc.AnswerCreationDate) AS LastAnswerDate,
    AVG(uc.ParagraphCount) AS AvgParagraphs,
    ROW_NUMBER() OVER (
      PARTITION BY uc.TagName
      ORDER BY SUM(uc.AnswerScore) DESC, COUNT(uc.AnswerId) DESC
    ) AS UserRankInTag
  FROM UserContributions uc
  GROUP BY
    uc.UserId,
    uc.TagName
), UserGeneralStats AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    (
      SELECT
        SUM(p.Score)
      FROM Posts p
      WHERE
        p.OwnerUserId = u.Id AND p.PostTypeId IN (1, 2)
    ) AS TotalPostScore,
    (
      SELECT
        COUNT(*)
      FROM Badges b
      WHERE
        b.UserId = u.Id AND b.Class = 1
    ) AS GoldBadges,
    (
      SELECT
        STRING_AGG(DISTINCT SUBSTRING(t.TagName, 1, 3), ',')
      FROM Tags t
      JOIN Posts p
        ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
      WHERE
        p.OwnerUserId = u.Id AND p.PostTypeId = 1
    ) AS TopTagPrefixes
  FROM Users u
  WHERE
    u.Reputation > 1000 AND u.DownVotes < u.UpVotes / 10
), RankedFinal AS (
  SELECT
    tgs.TagName,
    ugs.DisplayName,
    ugs.Reputation,
    tgs.TotalScore,
    tgs.TotalAnswers,
    tgs.AvgScore,
    (CAST(tgs.AcceptedAnswers AS REAL) / tgs.TotalAnswers) AS AcceptanceRate,
    ugs.GoldBadges,
    tgs.LastAnswerDate,
    EXTRACT(
      DAY
      FROM
        tgs.LastAnswerDate - LAG(tgs.LastAnswerDate, 1, tgs.LastAnswerDate) OVER (
          PARTITION BY tgs.UserId
          ORDER BY
            tgs.LastAnswerDate
        )
    ) AS DaysSincePreviousTagAnswer,
    ugs.TopTagPrefixes,
    COALESCE(ugs.DisplayName, 'Deleted User') AS FinalDisplayName,
    CASE
      WHEN ugs.Reputation > 100000
      THEN 'Top 0.1%'
      WHEN tgs.TotalScore > 500 AND ugs.GoldBadges > 5
      THEN 'Tag Expert'
      WHEN tgs.UserRankInTag = 1
      THEN 'Top Answerer in Tag'
      ELSE 'Contributor'
    END AS UserStatus
  FROM TagUserStats tgs
  JOIN UserGeneralStats ugs
    ON tgs.UserId = ugs.UserId
  WHERE
    tgs.UserRankInTag <= 5
    AND tgs.TotalAnswers > 10
)
SELECT
  *
FROM RankedFinal
WHERE
  DaysSincePreviousTagAnswer IS NOT NULL
  AND AcceptanceRate > 0.1
  AND TagName IN (
    SELECT
      TagName
    FROM Tags
    WHERE
      IsRequired = FALSE AND Count > 10000
  )
ORDER BY
  TagName,
  TotalScore DESC
LIMIT 500;