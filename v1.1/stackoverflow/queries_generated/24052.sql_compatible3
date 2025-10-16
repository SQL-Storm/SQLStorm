WITH
  question_data AS (
    SELECT
      p.Id                      AS QuestionId,
      p.Title,
      p.OwnerUserId,
      p.AnswerCount,
      p.AcceptedAnswerId,
      p.CreationDate           AS QuestionCreated,
      UNNEST(
        STRING_TO_ARRAY(
          SUBSTRING(p.Tags, 2, CHAR_LENGTH(p.Tags) - 2),
          '><'
        )
      )                         AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1
  ),
  tags_parsed AS (
    SELECT
      q.QuestionId,
      q.Tag,
      COUNT(*) FILTER (WHERE t.TagName = q.Tag) AS TagMatches
    FROM question_data q
    LEFT JOIN Tags t ON t.TagName = q.Tag
    GROUP BY q.QuestionId, q.Tag
  ),
  user_info AS (
    SELECT Id, Reputation, DisplayName
    FROM Users
  ),
  vote_sums AS (
    SELECT
      v.PostId,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)   AS UpVotes,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)   AS DownVotes,
      SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS TotalVotes
    FROM Votes v
    GROUP BY v.PostId
  ),
  first_answer AS (
    SELECT
      a.ParentId        AS QuestionId,
      MIN(a.CreationDate) AS FirstAnswerDate
    FROM Posts a
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
  ),
  duplicate_links AS (
    SELECT
      pl.PostId          AS SourceQuestionId,
      pl.RelatedPostId   AS DuplicateOfQuestionId
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3
  ),
  answer_rank AS (
    SELECT
      a.ParentId,
      a.Id            AS AnswerId,
      a.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.CreationDate) AS AnswerRank
    FROM Posts a
    WHERE a.PostTypeId = 2
  )
SELECT
  q.Title,
  COALESCE(ui.Reputation, 0)              AS OwnerReputation,
  COALESCE(vs.UpVotes, 0)                 AS UpVotes,
  COALESCE(vs.DownVotes, 0)               AS DownVotes,
  COALESCE(vs.TotalVotes, 0)              AS TotalVotes,
  COALESCE(ar_counts.TotalAnswers, 0)     AS TotalAnswers,
  COALESCE(af.FirstAnswerDate, NULL)      AS FirstAnswerDate,
  COUNT(DISTINCT q.Tag)                   AS TagCount,
  STRING_AGG(q.Tag, ',' ORDER BY q.Tag) FILTER (WHERE q.Tag IS NOT NULL) AS Tags,
  STRING_AGG(t.Tag, ',' ORDER BY t.Tag) FILTER (WHERE t.Tag IS NOT NULL) AS TagsMatched,
  CASE
    WHEN dl.DuplicateOfQuestionId IS NOT NULL THEN 'Duplicate'
    ELSE 'Primary'
  END                                      AS LinkStatus,
  STRING_AGG(CASE WHEN ar.AnswerRank = 1 THEN CAST(ar.AnswerId AS varchar) END, ',' ORDER BY ar.AnswerRank) FILTER (WHERE ar.AnswerRank = 1) AS FirstAnswers
FROM question_data q
LEFT JOIN user_info ui                 ON ui.Id = q.OwnerUserId
LEFT JOIN vote_sums vs                 ON vs.PostId = q.QuestionId
LEFT JOIN (
  SELECT ParentId AS QuestionId, COUNT(*) AS TotalAnswers
  FROM Posts
  WHERE PostTypeId = 2
  GROUP BY ParentId
) ar_counts                          ON ar_counts.QuestionId = q.QuestionId
LEFT JOIN first_answer af              ON af.QuestionId = q.QuestionId
LEFT JOIN duplicate_links dl           ON dl.SourceQuestionId = q.QuestionId
LEFT JOIN tags_parsed t                ON t.QuestionId = q.QuestionId
LEFT JOIN answer_rank ar               ON ar.ParentId = q.QuestionId
WHERE q.AnswerCount > 0
  AND (
    COALESCE(vs.TotalVotes, 0) + q.AnswerCount
  ) > 100
GROUP BY
  q.Title,
  q.QuestionCreated,
  q.QuestionId,
  q.OwnerUserId,
  q.AnswerCount,
  q.AcceptedAnswerId,
  ui.Reputation,
  vs.UpVotes,
  vs.DownVotes,
  vs.TotalVotes,
  ar_counts.TotalAnswers,
  af.FirstAnswerDate,
  dl.DuplicateOfQuestionId
ORDER BY q.QuestionCreated DESC
LIMIT 250;