WITH
  RankedAnswers AS (
    SELECT
      p.Id AS PostId,
      p.ParentId AS QuestionId,
      p.OwnerUserId,
      p.Score,
      p.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn,
      CASE
        WHEN p.OwnerUserId IS NULL THEN 'Anonymous'
        ELSE CAST(p.OwnerUserId AS VARCHAR(20))
      END AS OwnerIdentifier,
      COALESCE(u.DisplayName, 'Deleted User') AS OwnerDisplayName,
      COALESCE(u.Reputation, 0) AS OwnerReputation
    FROM Posts AS p
    LEFT JOIN Users AS u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 2
  ),
  AcceptedAnswerInfo AS (
    SELECT
      ps.Id AS QuestionId,
      ps.AcceptedAnswerId,
      ps.OwnerUserId AS QuestionOwnerUserId,
      ps.Title AS QuestionTitle,
      ps.CreationDate AS QuestionCreationDate,
      COALESCE(qs.DisplayName, 'Deleted User') AS QuestionOwnerDisplayName,
      COALESCE(qs.Reputation, 0) AS QuestionOwnerReputation,
      CASE
        WHEN ps.OwnerUserId IS NULL THEN 'Anonymous'
        ELSE CAST(ps.OwnerUserId AS VARCHAR(20))
      END AS QuestionOwnerIdentifier
    FROM Posts AS ps
    LEFT JOIN Users AS qs
      ON ps.OwnerUserId = qs.Id
    WHERE
      ps.PostTypeId = 1
  ),
  AnswerAcceptance AS (
    SELECT
      ra.QuestionId,
      COUNT(CASE WHEN ra.rn = 1 THEN 1 ELSE NULL END) AS HasAcceptedAnswer,
      SUM(CASE WHEN ra.rn = 1 THEN ra.Score ELSE 0 END) AS AcceptedAnswerScore,
      AVG(ra.OwnerReputation) AS AvgAcceptedAnswererReputation,
      MAX(ra.CreationDate) AS LatestAnswerDate
    FROM RankedAnswers AS ra
    GROUP BY
      ra.QuestionId
  )
SELECT
  COALESCE(que.QuestionTitle, 'Untitled Question') AS DisplayQuestionTitle,
  que.QuestionCreationDate,
  COALESCE(que.QuestionOwnerDisplayName, 'Unknown Owner') AS DisplayQuestionOwner,
  que.QuestionOwnerReputation,
  CASE
    WHEN que.AcceptedAnswerId IS NOT NULL THEN 'Yes'
    ELSE 'No'
  END AS IsAcceptedAnswerPresent,
  COALESCE(aa.HasAcceptedAnswer, 0) AS AnswerCountAccepted,
  COALESCE(aa.AcceptedAnswerScore, 0) AS ScoreOfAcceptedAnswer,
  COALESCE(aa.AvgAcceptedAnswererReputation, 0) AS AvgReputationOfAcceptedAnswerer,
  (
    SELECT
      COUNT(c.Id)
    FROM Comments AS c
    WHERE
      c.PostId = que.QuestionId
      AND c.CreationDate BETWEEN que.QuestionCreationDate AND aa.LatestAnswerDate
      AND c.Score < 0
  ) AS NegativeCommentCountOnQuestion,
  COALESCE(
    (
      SELECT
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)
      FROM Votes AS v
      WHERE
        v.PostId = que.QuestionId
    ),
    0
  ) AS NetVoteScoreOnQuestion,
  CASE
    WHEN que.QuestionOwnerUserId IS NULL THEN 'N/A'
    ELSE (
      SELECT
        CASE
          WHEN COUNT(b.Id) > 0 THEN 'HasBadges'
          ELSE 'NoBadges'
        END
      FROM Badges AS b
      WHERE
        b.UserId = que.QuestionOwnerUserId
        AND b.Date <= que.QuestionCreationDate
    )
  END AS QuestionOwnerBadgeStatus,
  COALESCE(
    (
      SELECT
        COUNT(ph.Id)
      FROM PostHistory AS ph
      WHERE
        ph.PostId = que.QuestionId
        AND ph.PostHistoryTypeId IN (4, 5, 6)
    ),
    0
  ) AS EditHistoryCount,
  LOWER(SUBSTRING(COALESCE(que.QuestionTitle, ''), 1, 10)) AS FirstTenCharsOfTitle,
  UPPER(COALESCE(CAST(que.QuestionOwnerReputation AS VARCHAR(10)), 'NULL_REP')) AS FormattedReputation
FROM AcceptedAnswerInfo AS que
LEFT JOIN AnswerAcceptance AS aa
  ON que.QuestionId = aa.QuestionId
WHERE
  que.QuestionTitle LIKE '%performance%'
  OR que.QuestionTitle LIKE '%benchmark%'
  OR EXISTS (
    SELECT
      1
    FROM Tags AS t
    WHERE
      t.TagName IN ('sql', 'performance', 'database')
      AND que.QuestionId IN (
        SELECT
          p_tags.Id
        FROM Posts AS p_tags
        WHERE
          p_tags.PostTypeId = 1
          AND (
            -- simple tag matching replacing FIND_IN_SET with standard LIKE checks
            p_tags.Tags LIKE '%<sql>%'
            OR p_tags.Tags LIKE '%<performance>%'
            OR p_tags.Tags LIKE '%<database>%'
          )
      )
  )
UNION ALL
SELECT
  'Aggregate Question Info' AS DisplayQuestionTitle,
  MIN(que.QuestionCreationDate) AS QuestionCreationDate,
  'Aggregated' AS QuestionOwnerDisplayName,
  AVG(que.QuestionOwnerReputation) AS QuestionOwnerReputation,
  'N/A' AS IsAcceptedAnswerPresent,
  SUM(COALESCE(aa.HasAcceptedAnswer, 0)) AS AnswerCountAccepted,
  AVG(COALESCE(aa.AcceptedAnswerScore, 0)) AS ScoreOfAcceptedAnswer,
  AVG(COALESCE(aa.AvgAcceptedAnswererReputation, 0)) AS AvgReputationOfAcceptedAnswerer,
  SUM(
    (
      SELECT
        COUNT(c.Id)
      FROM Comments AS c
      WHERE
        c.PostId = que.QuestionId
        AND c.CreationDate BETWEEN que.QuestionCreationDate AND aa.LatestAnswerDate
        AND c.Score < 0
    )
  ) AS NegativeCommentCountOnQuestion,
  SUM(COALESCE( (SELECT SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) FROM Votes AS v WHERE v.PostId = que.QuestionId), 0)) AS NetVoteScoreOnQuestion,
  'N/A' AS QuestionOwnerBadgeStatus,
  SUM(
    COALESCE(
      (
        SELECT
          COUNT(ph.Id)
        FROM PostHistory AS ph
        WHERE
          ph.PostId = que.QuestionId
          AND ph.PostHistoryTypeId IN (4, 5, 6)
      ),
      0
    )
  ) AS EditHistoryCount,
  'AGG_TITLE' AS FirstTenCharsOfTitle,
  'AGG_REP' AS FormattedReputation
FROM AcceptedAnswerInfo AS que
LEFT JOIN AnswerAcceptance AS aa
  ON que.QuestionId = aa.QuestionId
WHERE
  que.QuestionTitle LIKE '%performance%'
  OR que.QuestionTitle LIKE '%benchmark%';