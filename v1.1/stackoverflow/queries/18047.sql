WITH
  RankedUserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COUNT(p.Id) AS PostCount,
      ROW_NUMBER() OVER (
        ORDER BY
          u.Reputation DESC,
          u.CreationDate ASC
      ) AS ReputationRank
    FROM
      Users u
      LEFT JOIN Posts p
        ON u.Id = p.OwnerUserId
    WHERE
      u.Id > 0
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate
  ),
  RecentQuestionActivity AS (
    SELECT
      p.Id AS QuestionId,
      p.Title,
      p.CreationDate AS QuestionCreationDate,
      p.OwnerUserId,
      p.AnswerCount,
      p.FavoriteCount,
      ROW_NUMBER() OVER (
        ORDER BY
          p.CreationDate DESC
      ) AS ActivityRank
    FROM
      Posts p
    WHERE
      p.PostTypeId = 1
      AND p.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '1 year')
  ),
  HighReputationUsers AS (
    SELECT
      UserId
    FROM
      RankedUserActivity
    WHERE
      ReputationRank <= 100
  ),
  QuestionsWithMultipleAnswers AS (
    SELECT
      rq.QuestionId,
      rq.Title,
      rq.AnswerCount,
      rq.FavoriteCount,
      rua.DisplayName AS OwnerDisplayName,
      rua.Reputation AS OwnerReputation,
      rua.UserCreationDate
    FROM
      RecentQuestionActivity rq
      JOIN RankedUserActivity rua
        ON rq.OwnerUserId = rua.UserId
    WHERE
      rq.AnswerCount > 5
      AND rq.ActivityRank <= 50
    GROUP BY
      rq.QuestionId,
      rq.Title,
      rq.AnswerCount,
      rq.FavoriteCount,
      rua.DisplayName,
      rua.Reputation,
      rua.UserCreationDate
  ),
  TopQuestionsWithFavoredAnswers AS (
    SELECT
      q.QuestionId,
      q.Title AS QuestionTitle,
      q.OwnerDisplayName AS QuestionOwner,
      q.OwnerReputation AS QuestionOwnerReputation,
      a.Id AS AnswerId,
      a.OwnerUserId AS AnswerOwnerUserId,
      a.Score AS AnswerScore,
      u.DisplayName AS AnswerOwnerDisplayName,
      u.Reputation AS AnswerOwnerReputation,
      CASE
        WHEN q.QuestionId IS NOT NULL AND q.QuestionId IS NOT NULL AND q.QuestionId IS NOT NULL AND a.Id IS NOT NULL AND q.QuestionId IS NOT NULL THEN
          CASE WHEN /* preserve accepted-answer logic: compare AcceptedAnswerId if present in Posts */ NULLIF((SELECT p.AcceptedAnswerId FROM Posts p WHERE p.Id = q.QuestionId), NULL) = a.Id THEN 1 ELSE 0 END
        ELSE 0
      END AS IsAcceptedAnswer,
      ROW_NUMBER() OVER (
        PARTITION BY
          q.QuestionId
        ORDER BY
          a.Score DESC,
          a.CreationDate ASC
      ) AS AnswerRankWithinQuestion
    FROM
      QuestionsWithMultipleAnswers q
      JOIN Posts a
        ON q.QuestionId = a.ParentId
      LEFT JOIN Users u
        ON a.OwnerUserId = u.Id
    WHERE
      a.PostTypeId = 2
      AND a.CreationDate >= (cast('2024-10-01' as date) - INTERVAL '1 year')
  )
SELECT
  q.QuestionTitle,
  q.QuestionOwner,
  q.QuestionOwnerReputation,
  q.AnswerId,
  q.AnswerOwnerDisplayName,
  q.AnswerOwnerReputation,
  q.AnswerScore,
  q.IsAcceptedAnswer,
  (
    SELECT
      COUNT(*)
    FROM
      Comments c
    WHERE
      c.PostId = q.QuestionId
  ) AS QuestionCommentCount,
  (
    SELECT
      COUNT(*)
    FROM
      Comments c
    WHERE
      c.PostId = q.AnswerId
  ) AS AnswerCommentCount,
  COALESCE(
    (
      SELECT
        STRING_AGG(t.TagName, ', ')
      FROM
        Tags t
      WHERE
        EXISTS (
          SELECT 1
          FROM Posts p
          WHERE p.Id = q.QuestionId
            AND p.Tags LIKE '%' || t.TagName || '%'
        )
    ),
    'No Tags'
  ) AS RelatedTags
FROM
  TopQuestionsWithFavoredAnswers q
WHERE
  q.AnswerRankWithinQuestion <= 3
ORDER BY
  q.QuestionOwnerReputation DESC,
  q.AnswerScore DESC;