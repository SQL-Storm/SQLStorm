WITH
  RankedQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.Title AS QuestionTitle,
      p.OwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.AnswerCount,
      ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE
      p.PostTypeId = 1 AND p.ClosedDate IS NULL AND p.OwnerUserId IS NOT NULL
  ),
  HighReputationUsers AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName AS UserName,
      u.Reputation,
      ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS user_rn
    FROM Users u
    WHERE
      u.Id IN (
        SELECT OwnerUserId FROM Posts WHERE PostTypeId = 1
      )
  ),
  RecentAnswers AS (
    SELECT
      ans.Id AS AnswerId,
      ans.ParentId AS QuestionId,
      ans.OwnerUserId AS AnswerOwnerUserId,
      ans.CreationDate AS AnswerCreationDate,
      ans.Score AS AnswerScore,
      ROW_NUMBER() OVER (PARTITION BY ans.ParentId ORDER BY ans.CreationDate DESC) AS recent_ans_rn
    FROM Posts ans
    WHERE
      ans.PostTypeId = 2 AND ans.ClosedDate IS NULL
  ),
  QuestionActivity AS (
    SELECT
      p.Id AS QuestionId,
      COUNT(c.Id) AS CommentCount,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
    FROM Posts p
    LEFT JOIN Comments c
      ON p.Id = c.PostId
    LEFT JOIN Votes v
      ON p.Id = v.PostId
    WHERE
      p.PostTypeId = 1
    GROUP BY
      p.Id
  ),
  TagAnalysis AS (
    SELECT
      p.Id AS QuestionId,
      t.TagName,
      CASE
        WHEN p.Tags LIKE '%' || t.TagName || '%' THEN 1
        ELSE 0
      END AS TagPresent
    FROM Posts p
    CROSS JOIN Tags t
    WHERE
      p.PostTypeId = 1 AND p.Tags IS NOT NULL
  )
SELECT
  rq.QuestionId,
  rq.QuestionTitle,
  hr.UserName AS TopReputationUserName,
  hr.Reputation AS TopReputationUserReputation,
  rq.QuestionScore,
  rq.AnswerCount,
  ra.AnswerId AS LatestAnswerId,
  ra.AnswerScore AS LatestAnswerScore,
  qa.CommentCount AS QuestionTotalComments,
  qa.UpVoteCount AS QuestionTotalUpvotes,
  qa.DownVoteCount AS QuestionTotalDownvotes,
  ta.TagName AS MostFrequentTag,
  CASE
    WHEN rq.OwnerUserId = hr.UserId THEN 'Owner is Top User'
    ELSE 'Owner is not Top User'
  END AS OwnerReputationStatus,
  rq.rn,
  hr.user_rn
FROM RankedQuestions rq
LEFT JOIN HighReputationUsers hr
  ON hr.user_rn <= 10 -- limit which users are considered in join
LEFT JOIN RecentAnswers ra
  ON rq.QuestionId = ra.QuestionId AND ra.recent_ans_rn = 1
LEFT JOIN QuestionActivity qa
  ON rq.QuestionId = qa.QuestionId
LEFT JOIN TagAnalysis ta
  ON rq.QuestionId = ta.QuestionId AND ta.TagPresent = 1
WHERE
  rq.rn <= 100 -- Focus on top 100 questions by score
  AND EXISTS (
    SELECT 1 FROM Posts p_sub WHERE p_sub.ParentId = rq.QuestionId AND p_sub.PostTypeId = 2
  )
GROUP BY
  rq.QuestionId,
  rq.QuestionTitle,
  hr.UserName,
  hr.Reputation,
  rq.QuestionScore,
  rq.AnswerCount,
  ra.AnswerId,
  ra.AnswerScore,
  qa.CommentCount,
  qa.UpVoteCount,
  qa.DownVoteCount,
  ta.TagName,
  rq.OwnerUserId,
  hr.UserId,
  rq.rn,
  hr.user_rn,
  CASE
    WHEN rq.OwnerUserId = hr.UserId THEN 'Owner is Top User'
    ELSE 'Owner is not Top User'
  END
HAVING
  COUNT(ta.TagName) > 0
ORDER BY
  rq.rn,
  hr.user_rn;