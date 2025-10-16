-- {"query": "22046.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 804} 
WITH TopQuestions AS (
    SELECT Id, OwnerUserId, Title, Score, CreationDate, Tags, AnswerCount,
           ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY Score DESC) AS Rn
    FROM Posts
    WHERE PostTypeId = 1 AND Score > 50 AND AnswerCount > 5
),
GoldBadgeUsers AS (
    SELECT UserId, COUNT(*) AS GoldCount
    FROM Badges
    WHERE Class = 1
    GROUP BY UserId
    HAVING COUNT(*) >= 3
),
UserPostStats AS (
    SELECT u.Id AS UserId, u.DisplayName,
           COALESCE(SUM(p.Score), 0) AS TotalScore,
           COUNT(DISTINCT p.Id) AS PostCount,
           AVG(LENGTH(p.Body)) AS AvgBodyLength,
           STRING_AGG(DISTINCT SUBSTRING(t.TagName, 1, CASE WHEN LENGTH(t.TagName) > 10 THEN 10 ELSE LENGTH(t.TagName) END), ', ') AS TopTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1,2)
    LEFT JOIN Tags t ON EXISTS (SELECT 1 FROM UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS tag WHERE tag = t.TagName)
    WHERE u.CreationDate < '2020-01-01'::timestamp
    GROUP BY u.Id, u.DisplayName
)
SELECT tq.Id AS QuestionId, tq.Title,
       ups.DisplayName, ups.TotalScore, ups.PostCount,
       gbu.GoldCount,
       tq.Score AS QuestionScore,
       COALESCE(accepted.AnswerCount, 0) AS AcceptedAnswers,
       CASE WHEN ups.TotalScore > 1000 THEN 'High Contributor' ELSE 'Regular' END AS UserCategory,
       (EXTRACT(YEAR FROM AGE(NOW(), tq.CreationDate)) * 365 + EXTRACT(DAY FROM AGE(NOW(), tq.CreationDate))) AS DaysOld,
       LENGTH(tq.Title) / NULLIF(tq.AnswerCount, 0) AS TitleLengthPerAnswer,
       ups.TopTags
FROM TopQuestions tq
JOIN UserPostStats ups ON tq.OwnerUserId = ups.UserId
JOIN GoldBadgeUsers gbu ON tq.OwnerUserId = gbu.UserId
LEFT JOIN (SELECT ParentId, COUNT(*) AS AnswerCount
           FROM Posts
           WHERE PostTypeId = 2 AND AcceptedAnswerId IS NOT NULL
           GROUP BY ParentId) accepted ON tq.Id = accepted.ParentId
WHERE tq.Rn = 1
  AND ups.PostCount > 10
  AND (tq.Score > 100 OR gbu.GoldCount > 5)
ORDER BY ups.TotalScore DESC, tq.Score DESC
UNION ALL
SELECT NULL, 'Summary Row',
       NULL, SUM(ups.TotalScore), COUNT(DISTINCT ups.UserId),
       SUM(gbu.GoldCount),
       AVG(tq.Score),
       SUM(COALESCE(accepted.AnswerCount, 0)),
       'Total',
       NULL,
       NULL,
       STRING_AGG(DISTINCT ups.TopTags, '; ')
FROM TopQuestions tq
JOIN UserPostStats ups ON tq.OwnerUserId = ups.UserId
JOIN GoldBadgeUsers gbu ON tq.OwnerUserId = gbu.UserId
LEFT JOIN (SELECT ParentId, COUNT(*) AS AnswerCount
           FROM Posts
           WHERE PostTypeId = 2 AND AcceptedAnswerId IS NOT NULL
           GROUP BY ParentId) accepted ON tq.Id = accepted.ParentId
WHERE tq.Rn = 1 AND ups.PostCount > 10
  AND (tq.Score > 100 OR gbu.GoldCount > 5);