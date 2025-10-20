-- {"query": "10.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1014} 
WITH RankedPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.Tags,
    p.PostTypeId,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        p.Score DESC,
        p.ViewCount DESC,
        p.CreationDate DESC
    ) AS rn
  FROM Posts p
  WHERE p.PostTypeId IN (1,2)
),
TopQuestions AS (
  SELECT
    rp.Id AS QuestionId,
    rp.Title,
    rp.CreationDate AS QuestionCreationDate,
    rp.Score AS QuestionScore,
    rp.ViewCount AS QuestionViews,
    ru.DisplayName AS QuestionOwner,
    ru.Reputation AS OwnerReputation,
    DATE_PART('year', AGE(rp.CreationDate)) AS AgeYears,
    CASE
      WHEN rp.Tags ~ '<[^>]+>' THEN
        lower(regexp_replace(substr(rp.Tags, 2, length(rp.Tags) - 2), '><', ',', 'g'))
      ELSE ''
    END AS TagList,
    CASE
      WHEN rp.rn = 1 THEN true ELSE false
    END AS IsTopInCategory
  FROM RankedPosts rp
  LEFT JOIN Users ru ON rp.OwnerUserId = ru.Id
  WHERE rp.PostTypeId = 1 AND rp.rn = 1
),
CorrelatedAnswers AS (
  SELECT
    a.Id AS AnswerId,
    a.ParentId AS QuestionId,
    a.Score AS AnswerScore,
    a.ViewCount AS AnswerViews,
    a.OwnerUserId AS AnswerOwnerId,
    u2.DisplayName AS AnswerOwnerName,
    u2.Reputation AS AnswerOwnerRep,
    ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate DESC) AS rn_ans
  FROM Posts a
  LEFT JOIN Users u2 ON a.OwnerUserId = u2.Id
  WHERE a.PostTypeId = 2
),
TopQuestionsWithBestAnswer AS (
  SELECT
    tq.QuestionId,
    tq.Title AS QuestionTitle,
    tq.QuestionCreationDate,
    tq.QuestionScore,
    tq.QuestionViews,
    tq.QuestionOwner,
    tq.OwnerReputation,
    tq.AgeYears,
    tq.TagList,
    ta.AnswerId,
    ta.AnswerScore,
    ta.AnswerViews,
    ta.AnswerOwnerName,
    ta.AnswerOwnerRep,
    ta.rn_ans
  FROM TopQuestions tq
  LEFT JOIN CorrelatedAnswers ta
    ON tq.QuestionId = ta.QuestionId
  WHERE ta.rn_ans = 1 OR ta.AnswerId IS NULL
),
WindowedVotes AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.CreateDate AS VoteDate,
    v.UserId,
    v.BountyAmount,
    ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreateDate DESC) AS rn_vote
  FROM Votes v
  WHERE v.VoteTypeId IN (2,3,4,6,10,11,14,15,16)
)
SELECT
  q.QuestionId,
  q.QuestionTitle,
  q.QuestionCreationDate,
  q.QuestionScore,
  q.QuestionViews,
  q.QuestionOwner,
  q.OwnerReputation,
  q.AgeYears,
  COALESCE(NULLIF(q.TagList, ''), '[]') AS TagsJson,
  q.AnswerId,
  q.AnswerScore,
  q.AnswerViews,
  q.AnswerOwnerName,
  q.AnswerOwnerRep,
  q.rn_ans AS BestAnswerRank,
  vw.VoteDate AS LastVoteDate,
  vw.VoteTypeId AS LastVoteType,
  vw.UserId AS LastVoteUserId,
  (SELECT COUNT(*) FROM Votes v2 WHERE v2.PostId = q.QuestionId AND v2.VoteTypeId = 2) AS UpVotesOnQuestion,
  (SELECT COUNT(*) FROM Votes v2 WHERE v2.PostId = q.QuestionId AND v2.VoteTypeId = 3) AS DownVotesOnQuestion,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = q.QuestionId) AS RelatedLinksCount,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.QuestionId) AS CommentCount,
  (SELECT MAX(p.LastActivityDate) FROM Posts p WHERE p.ParentId = q.QuestionId OR p.Id = q.QuestionId) AS LastActivityForQuestion
FROM TopQuestionsWithBestAnswer q
LEFT JOIN WindowedVotes vw
  ON q.QuestionId = vw.PostId AND vw.rn_vote = 1
ORDER BY q.QuestionCreationDate DESC, q.QuestionViews DESC
LIMIT 100;