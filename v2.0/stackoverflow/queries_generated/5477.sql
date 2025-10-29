-- {"query": "5477.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1077} 
WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.Body,
    p.LastActivityDate,
    p.CommentCount,
    p.FavoriteCount,
    p.AcceptedAnswerId,
    p.ParentId,
    p.LastEditDate,
    p.LastEditorUserId,
    p.OwnerDisplayName,
    p.ContentLicense,
    p.Title IS NOT NULL AS HasTitle,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        p.Score DESC,
        p.ViewCount DESC,
        p.CreationDate ASC
    ) AS rn_by_type
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE
    p.CreationDate >= CURRENT_DATE - INTERVAL '365 days'
    OR p.ViewCount > 1000
),
TopQuestions AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.OwnerUserId,
    rp.OwnerDisplayName,
    rp.Tags,
    rp.LastActivityDate,
    ROW_NUMBER() OVER (ORDER BY rp.Score DESC, rp.ViewCount DESC, rp.CreationDate DESC) AS qrank
  FROM RankedPosts rp
  WHERE rp.PostTypeId = 1 -- Questions
    AND rp.rn_by_type = 1
),
TagMentions AS (
  SELECT
    q.PostId,
    unnest(string_to_array(
      substring(q.Tags, 2, length(q.Tags) - 2),
      '><'
    )) AS TagName
  FROM TopQuestions q
),
TagStats AS (
  SELECT
    t.TagName,
    COUNT(*) AS QuestionCount,
    AVG(q.Score) AS AvgScore,
    SUM(q.ViewCount) AS TotalViews
  FROM TagMentions t
  JOIN TopQuestions q ON q.PostId = t.PostId
  GROUP BY t.TagName
),
CoOccurrence AS (
  SELECT
    t1.TagName AS TagA,
    t2.TagName AS TagB,
    COUNT(*) AS CoCount
  FROM TagMentions t1
  JOIN TagMentions t2
    ON t1.PostId = t2.PostId
   AND t1.TagName < t2.TagName
  GROUP BY t1.TagName, t2.TagName
),
PopularPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.Tags,
    (SELECT STRING_AGG(CONCAT('u', v.UserId, ':', v.VoteTypeId), ',')
     FROM Votes v
     WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3) ) AS RecentVotes
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.ViewCount >= 500
    AND p.Score >= 5
)
SELECT
  qp.PostId AS QuestionPostId,
  qp.Title AS QuestionTitle,
  qp.CreationDate AS QuestionCreated,
  qp.Score AS QuestionScore,
  qp.ViewCount AS QuestionViews,
  qi.PostId AS AnswerPostId,
  aq.OwnerUserId AS AnswerOwnerId,
  aq.OwnerDisplayName AS AnswerOwnerName,
  aq.CreationDate AS AnswerDate,
  aq.Score AS AnswerScore,
  to_char(qp.LastActivityDate, 'YYYY-MM-DD HH24:MI:SS') AS LastActivity,
  ta.TagName AS TagInQuestion,
  ts.QuestionCount AS TagQuestionCount,
  ts.AvgScore AS TagAvgScore,
  ts.TotalViews AS TagTotalViews,
  COALESCE(co.TagA, NULL) AS TagA,
  COALESCE(co.TagB, NULL) AS TagB,
  co.CoCount AS TagCoOccur
FROM TopQuestions qp
LEFT JOIN Posts a ON a.ParentId = qp.PostId AND a.PostTypeId = 2
LEFT JOIN Users aq ON a.OwnerUserId = aq.Id
LEFT JOIN TagMentions ta ON ta.PostId = qp.PostId
LEFT JOIN TagStats ts ON ts.TagName = ta.TagName
LEFT JOIN (
  SELECT
    p.Id AS PostId,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.CreationDate,
    p.Score
  FROM Posts p
  WHERE p.PostTypeId = 2
) qi ON qi.PostId = a.Id
LEFT JOIN PopularPosts pp ON pp.PostId = qp.PostId
LEFT JOIN (
  SELECT
    TagA,
    TagB,
    CoCount
  FROM CoOccurrence
) co ON true
ORDER BY qp.Score DESC, qp.ViewCount DESC
LIMIT 100;