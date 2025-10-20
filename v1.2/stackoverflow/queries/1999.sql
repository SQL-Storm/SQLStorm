WITH RecursiveTagReport AS (
  SELECT
    p.Id AS QuestionId,
    u.DisplayName AS Owner,
    unnest(string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags) - 2), '><')) AS Tag,
    p.ViewCount,
    p.Score,
    p.CreationDate AS QuestionCreated,
    ba.BadgeSummary,
    a_stats.AnswerCount,
    ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.Score DESC, a_stats.MaxAnswerCreationDate DESC) AS AnswerRank
  FROM Posts p
  INNER JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT ParentId,
           COUNT(*) AS AnswerCount,
           MAX(CreationDate) AS MaxAnswerCreationDate
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY ParentId
  ) a_stats ON a_stats.ParentId = p.Id
  LEFT JOIN (
    SELECT UserId,
           string_agg(DISTINCT (Name || '(' || Class || ')'), ', ') AS BadgeSummary
    FROM Badges
    GROUP BY UserId
  ) ba ON ba.UserId = p.OwnerUserId
  WHERE p.PostTypeId = 1
),
AnswersExpanded AS (
  SELECT
    p_yes.Id AS AnswerId,
    re.QuestionId,
    re.Owner AS QuestionOwner,
    re.Tag AS QuestionTag,
    p_yes.Score AS AnswerScore,
    p_yes.CreationDate AS AnswerCreated,
    p_yes.OwnerUserId AS AnswerOwnerUserId,
    u_a.DisplayName AS AnswerOwner,
    ROW_NUMBER() OVER (PARTITION BY p_yes.ParentId ORDER BY p_yes.Score DESC, p_yes.CreationDate DESC) AS AnswerRow
  FROM Posts p_yes
  INNER JOIN RecursiveTagReport re ON p_yes.ParentId = re.QuestionId
  LEFT JOIN Users u_a ON p_yes.OwnerUserId = u_a.Id
  WHERE p_yes.PostTypeId = 2
)
SELECT
  re.QuestionId,
  re.Owner,
  re.Tag,
  re.ViewCount,
  re.Score AS QuestionScore,
  re.QuestionCreated,
  re.BadgeSummary,
  re.AnswerCount,
  ae.AnswerId,
  ae.AnswerScore,
  ae.AnswerCreated,
  ae.AnswerOwnerUserId,
  ae.AnswerOwner
FROM RecursiveTagReport re
LEFT JOIN AnswersExpanded ae
  ON re.QuestionId = ae.QuestionId
  AND ae.AnswerRow = 1
GROUP BY
  re.QuestionId,
  re.Owner,
  re.Tag,
  re.ViewCount,
  re.Score,
  re.QuestionCreated,
  re.BadgeSummary,
  re.AnswerCount,
  ae.AnswerId,
  ae.AnswerScore,
  ae.AnswerCreated,
  ae.AnswerOwnerUserId,
  ae.AnswerOwner;