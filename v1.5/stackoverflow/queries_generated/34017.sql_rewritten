-- {"query": "34017.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 836} 
WITH RecentHighRepUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation
    FROM Users u
    WHERE u.Reputation > 50000 AND u.CreationDate >= cast('2024-10-01' as date) - INTERVAL '5 years'
),
UserBadgeStats AS (
    SELECT b.UserId,
           COUNT(*) AS TotalBadges,
           COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
           COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
           COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
           MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    WHERE b.UserId IN (SELECT Id FROM RecentHighRepUsers)
    GROUP BY b.UserId
),
TopQuestions AS (
    SELECT p.Id, p.OwnerUserId, p.Title, p.Score, p.ViewCount, p.CreationDate,
           COALESCE(a.AnswerCount,0) AS AnswerCount,
           STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><') AS TagList
    FROM Posts p
    LEFT JOIN (
        SELECT ParentId, COUNT(*) AS AnswerCount
        FROM Posts
        WHERE PostTypeId = 2
        GROUP BY ParentId
    ) a ON p.Id = a.ParentId
    WHERE p.PostTypeId = 1 AND p.Score >= 10
),
TagPopularity AS (
    SELECT unnest(TagList) AS Tag, COUNT(*) AS QuestionCount
    FROM TopQuestions
    GROUP BY Tag
),
RecentEdits AS (
    SELECT ph.PostId, ph.UserId, u.DisplayName, ph.PostHistoryTypeId, ph.CreationDate,
           ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS RN
    FROM PostHistory ph
    JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
LatestEditsPerPost AS (
    SELECT PostId, UserId, DisplayName, PostHistoryTypeId, CreationDate
    FROM RecentEdits
    WHERE RN = 1
),
AnswerStats AS (
    SELECT p.OwnerUserId, COUNT(*) AS TotalAnswers, AVG(p.Score) AS AvgAnswerScore
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.OwnerUserId
)
SELECT ru.Id AS UserId, ru.DisplayName, ru.Reputation,
       ubs.TotalBadges, ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges, ubs.LastBadgeDate,
       q.Id AS QuestionId, q.Title, q.Score AS QuestionScore, q.ViewCount, q.AnswerCount, q.CreationDate AS QuestionCreationDate,
       array_to_string(q.TagList, ', ') AS Tags,
       tp.Tag AS PopularTag, tp.QuestionCount AS PopularityOfTag,
       le.PostHistoryTypeId AS LastEditType, le.CreationDate AS LastEditDate, le.DisplayName AS LastEditorName,
       COALESCE(a.TotalAnswers,0) AS TotalAnswersByUser, COALESCE(a.AvgAnswerScore,0) AS AvgAnswerScoreByUser
FROM RecentHighRepUsers ru
LEFT JOIN UserBadgeStats ubs ON ru.Id = ubs.UserId
LEFT JOIN TopQuestions q ON q.OwnerUserId = ru.Id
LEFT JOIN TagPopularity tp ON tp.Tag = ANY(q.TagList)
LEFT JOIN LatestEditsPerPost le ON le.PostId = q.Id
LEFT JOIN AnswerStats a ON a.OwnerUserId = ru.Id
WHERE q.CreationDate >= cast('2024-10-01' as date) - INTERVAL '1 year'
ORDER BY ru.Reputation DESC, ubs.TotalBadges DESC, q.Score DESC, tp.QuestionCount DESC
LIMIT 100;