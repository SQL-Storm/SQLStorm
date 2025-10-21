-- {"query": "50081.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 905} 
WITH UserAnswerTags AS (
  SELECT
    a.OwnerUserId,
    a.Id AS AnswerId,
    a.Score AS AnswerScore,
    a.CreationDate AS AnswerCreationDate,
    q.CreationDate AS QuestionCreationDate,
    q.ViewCount AS QuestionViewCount,
    UNNEST(STRING_TO_ARRAY(SUBSTRING(q.Tags, 2, LENGTH(q.Tags) - 2), '><')) AS TagName
  FROM Posts AS a
  JOIN Posts AS q
    ON a.ParentId = q.Id
  WHERE
    a.PostTypeId = 2 -- Answer
    AND q.PostTypeId = 1 -- Question
    AND a.OwnerUserId IS NOT NULL
    AND q.Tags IS NOT NULL
), UserTagStats AS (
  SELECT
    OwnerUserId,
    TagName,
    COUNT(*) AS AnswersInTag,
    SUM(AnswerScore) AS ScoreInTag,
    AVG(AnswerScore) AS AvgScoreInTag,
    SUM(QuestionViewCount) AS TotalQuestionViewsInTag,
    AVG(EXTRACT(EPOCH FROM (
      AnswerCreationDate - QuestionCreationDate
    ))) AS AvgTimeToAnswerSeconds
  FROM UserAnswerTags
  GROUP BY
    OwnerUserId,
    TagName
), RankedUserTags AS (
  SELECT
    uts.*,
    ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY ScoreInTag DESC, AnswersInTag DESC) AS TagRank
  FROM UserTagStats uts
), UserPostCounts AS (
  SELECT
    OwnerUserId,
    SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
  FROM Posts
  WHERE
    OwnerUserId IS NOT NULL
    AND PostTypeId IN (1, 2)
  GROUP BY
    OwnerUserId
)
SELECT
  u.Id AS UserId,
  u.DisplayName,
  u.Reputation,
  u.UpVotes AS TotalUpVotes,
  upc.AnswerCount,
  upc.QuestionCount,
  rut.TagName AS PrimaryTag,
  rut.AnswersInTag AS PrimaryTagAnswers,
  rut.ScoreInTag AS PrimaryTagScore,
  rut.AvgScoreInTag AS PrimaryTagAvgScore,
  rut.AvgTimeToAnswerSeconds AS PrimaryTagAvgAnswerTime,
  (
    SELECT
      COUNT(*)
    FROM Badges b
    WHERE
      b.UserId = u.Id AND b.Name = rut.TagName AND b.TagBased = true AND b.Class = 1
  ) AS GoldTagBadges,
  (
    SELECT
      COUNT(*)
    FROM Badges b
    WHERE
      b.UserId = u.Id AND b.Name = rut.TagName AND b.TagBased = true AND b.Class = 2
  ) AS SilverTagBadges,
  (
    SELECT
      AVG(c.Score)
    FROM Comments c
    JOIN Posts p
      ON c.PostId = p.Id
    WHERE
      p.OwnerUserId = u.Id AND p.ParentId IN (
        SELECT
          Id
        FROM Posts q
        WHERE
          q.PostTypeId = 1 AND q.Tags LIKE CONCAT('%<', rut.TagName, '>%')
      )
  ) AS AvgCommentScoreOnPrimaryTagAnswers
FROM Users u
JOIN RankedUserTags rut
  ON u.Id = rut.OwnerUserId
JOIN UserPostCounts upc
  ON u.Id = upc.OwnerUserId
WHERE
  rut.TagRank = 1
  AND u.Reputation > 10000
  AND upc.AnswerCount > 50
  AND upc.AnswerCount > upc.QuestionCount * 2
ORDER BY
  (rut.ScoreInTag * LOG(u.Reputation)) DESC,
  u.Reputation DESC
LIMIT 100;