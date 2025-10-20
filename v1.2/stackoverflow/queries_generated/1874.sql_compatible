WITH QuestionScores AS (
  SELECT
    p.Id AS QuestionId,
    p.Title,
    p.OwnerUserId,
    u.DisplayName,
    p.Score,
    p.CreationDate,
    p.Body,
    COALESCE(p.AnswerCount, 0) AS AnswerCount,
    COALESCE(
      (
        SELECT SUM(
          CASE vt.Name
            WHEN 'UpMod' THEN 1
            WHEN 'DownMod' THEN -1
            ELSE 0
          END
        )
        FROM VoteTypes vt
        JOIN Votes v ON v.VoteTypeId = vt.Id
        WHERE v.PostId = p.Id
      ),
      0
    ) AS WeightedVoteScore
  FROM Posts p
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  WHERE p.PostTypeId = 1
),
AnswerScores AS (
  SELECT
    a.Id AS AnswerId,
    a.ParentId AS QuestionId,
    a.OwnerUserId,
    ua.DisplayName,
    a.Score,
    a.CreationDate,
    a.Body,
    COALESCE(
      (
        SELECT SUM(
          CASE vt.Name
            WHEN 'UpMod' THEN 1
            WHEN 'DownMod' THEN -1
            ELSE 0
          END
        )
        FROM VoteTypes vt
        JOIN Votes v ON v.VoteTypeId = vt.Id
        WHERE v.PostId = a.Id
      ),
      0
    ) AS WeightedVoteScore
  FROM Posts a
  LEFT JOIN Users ua ON ua.Id = a.OwnerUserId
  WHERE a.PostTypeId = 2
),
QuestionAggregates AS (
  SELECT
    q.QuestionId,
    q.Title,
    q.OwnerUserId,
    q.DisplayName,
    q.Score AS QuestionScore,
    q.CreationDate AS QuestionCreationDate,
    q.Body AS QuestionBody,
    q.AnswerCount,
    q.WeightedVoteScore AS QuestionWeightedVoteScore,
    COUNT(a.AnswerId) AS AnswersCount,
    SUM(a.Score) AS AnswersTotalScore,
    SUM(a.WeightedVoteScore) AS AnswersTotalWeightedVoteScore
  FROM QuestionScores q
  LEFT JOIN AnswerScores a ON a.QuestionId = q.QuestionId
  GROUP BY
    q.QuestionId,
    q.Title,
    q.OwnerUserId,
    q.DisplayName,
    q.Score,
    q.CreationDate,
    q.Body,
    q.AnswerCount,
    q.WeightedVoteScore
),
TopAnswers AS (
  SELECT
    a.AnswerId,
    a.QuestionId,
    a.OwnerUserId,
    a.DisplayName,
    a.Score,
    a.CreationDate,
    a.Body,
    a.WeightedVoteScore,
    ROW_NUMBER() OVER (PARTITION BY a.QuestionId ORDER BY a.Score DESC, a.WeightedVoteScore DESC, a.CreationDate ASC) AS rn
  FROM AnswerScores a
)
SELECT
  qa.QuestionId,
  qa.Title,
  qa.OwnerUserId,
  qa.DisplayName,
  qa.QuestionScore,
  qa.QuestionCreationDate,
  qa.QuestionBody,
  qa.AnswerCount,
  qa.QuestionWeightedVoteScore,
  qa.AnswersCount,
  qa.AnswersTotalScore,
  qa.AnswersTotalWeightedVoteScore,
  ta.AnswerId AS TopAnswerId,
  ta.OwnerUserId AS TopAnswerOwnerUserId,
  ta.DisplayName AS TopAnswerDisplayName,
  ta.Score AS TopAnswerScore,
  ta.CreationDate AS TopAnswerCreationDate,
  ta.Body AS TopAnswerBody,
  ta.WeightedVoteScore AS TopAnswerWeightedVoteScore
FROM QuestionAggregates qa
LEFT JOIN TopAnswers ta
  ON ta.QuestionId = qa.QuestionId AND ta.rn = 1
ORDER BY qa.QuestionId;