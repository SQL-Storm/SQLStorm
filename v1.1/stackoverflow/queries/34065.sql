WITH TopUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation,
           COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotesReceived,
           COALESCE(COUNT(b.Id), 0) AS BadgeCount,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COALESCE(COUNT(b.Id),0) DESC) AS rn
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 2
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING u.Reputation > 1000
),
TopTags AS (
    SELECT t.TagName,
           COUNT(*) FILTER (WHERE pt.TagName IS NOT NULL) AS QuestionCount,
           AVG(p.Score) AS AvgScore,
           SUM(p.ViewCount) AS TotalViews
    FROM Tags t
    JOIN Posts p ON p.PostTypeId = 1
    -- expand tag string into rows in a dialect-agnostic way using a derived table with recursive splitting or string functions
    -- here we emulate unnest(string_to_array(...)) by using a simple splitting approach assuming tags use format '<tag1><tag2>'
    JOIN (
      SELECT p2.Id AS PostId,
             TRIM(tag) AS TagName
      FROM Posts p2,
           (SELECT 1) AS dummy
      CROSS JOIN LATERAL (
        SELECT regexp_split_to_table(substring(p2.Tags FROM 2 FOR length(p2.Tags)-2), '><') AS tag
      ) AS s
    ) AS pt ON pt.PostId = p.Id AND pt.TagName = t.TagName
    GROUP BY t.TagName
    HAVING COUNT(*) FILTER (WHERE pt.TagName IS NOT NULL) > 50
),
UserTagActivity AS (
    SELECT tu.Id AS UserId, tu.DisplayName, tu.Reputation, tt.TagName,
           COUNT(p.Id) AS QuestionsAsked,
           SUM(COALESCE(p.Score,0)) AS TotalScore
    FROM TopUsers tu
    JOIN Posts p ON p.OwnerUserId = tu.Id AND p.PostTypeId = 1
    JOIN (
      SELECT p2.Id AS PostId,
             TRIM(tag) AS TagName
      FROM Posts p2,
           (SELECT 1) AS dummy
      CROSS JOIN LATERAL (
        SELECT regexp_split_to_table(substring(p2.Tags FROM 2 FOR length(p2.Tags)-2), '><') AS tag
      ) AS s
    ) AS pt ON pt.PostId = p.Id
    JOIN TopTags tt ON tt.TagName = pt.TagName
    GROUP BY tu.Id, tu.DisplayName, tu.Reputation, tt.TagName
),
PostAnswerActivity AS (
    SELECT p.ParentId AS QuestionId, COUNT(p.Id) AS AnswerCount,
           AVG(p.Score) AS AvgAnswerScore,
           MAX(p.CreationDate) AS LastAnswerDate
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
),
QuestionDetails AS (
    SELECT p.Id, p.Title, p.CreationDate, p.Score AS QuestionScore, p.ViewCount,
           p.AnswerCount, p.FavoriteCount,
           pa.AnswerCount AS ActualAnswerCount, pa.AvgAnswerScore, pa.LastAnswerDate,
           u.DisplayName AS OwnerName, u.Reputation AS OwnerReputation,
           p.Tags
    FROM Posts p
    LEFT JOIN PostAnswerActivity pa ON pa.QuestionId = p.Id
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
      AND p.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
      AND p.Score > 10
)
SELECT tu.DisplayName AS "User",
       tu.Reputation,
       tu.UpVotesReceived,
       tu.BadgeCount,
       ut.TagName,
       ut.QuestionsAsked,
       ut.TotalScore AS TagScore,
       q.Title AS SampleQuestionTitle,
       q.QuestionScore,
       q.ViewCount,
       q.FavoriteCount,
       COALESCE(q.ActualAnswerCount, 0) AS Answers,
       COALESCE(q.AvgAnswerScore, 0) AS AvgAnswerScore,
       q.LastAnswerDate,
       q.OwnerName AS QuestionOwner,
       q.OwnerReputation AS QuestionOwnerReputation
FROM TopUsers tu
JOIN UserTagActivity ut ON ut.UserId = tu.Id
LEFT JOIN (
    SELECT qd.*
    FROM QuestionDetails qd
    JOIN (
      SELECT q2.Id AS QuestionId, TRIM(tag) AS TagName
      FROM QuestionDetails q2,
           (SELECT 1) AS dummy
      CROSS JOIN LATERAL (
        SELECT regexp_split_to_table(substring(q2.Tags FROM 2 FOR length(q2.Tags)-2), '><') AS tag
      ) AS s
    ) AS qt ON qt.QuestionId = qd.Id AND qt.TagName = ut.TagName
    WHERE qd.OwnerName = tu.DisplayName
    ORDER BY qd.QuestionScore DESC, qd.ViewCount DESC
    LIMIT 1
) q ON true
WHERE tu.rn <= 10
ORDER BY tu.Reputation DESC, ut.QuestionsAsked DESC, q.QuestionScore DESC;