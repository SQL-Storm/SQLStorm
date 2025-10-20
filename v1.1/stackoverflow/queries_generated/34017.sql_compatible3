WITH RecentHighRepUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation
    FROM Users u
    WHERE u.Reputation > 50000
      AND u.CreationDate >= DATE '2024-10-01' - INTERVAL '5' YEAR
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
           COALESCE(a.AnswerCount, 0) AS AnswerCount,
           -- convert tags like '<tag1><tag2>' into an array by removing leading/trailing angle brackets and splitting on '><'
           -- use standard SQL: substring + length, then split on '><'
           CASE
             WHEN p.Tags IS NULL THEN NULL
             WHEN LENGTH(p.Tags) >= 2 THEN
               regexp_split_to_array(substring(p.Tags FROM 2 FOR (LENGTH(p.Tags) - 2)), '><')
             ELSE
               regexp_split_to_array(p.Tags, '><')
           END AS TagList
    FROM Posts p
    LEFT JOIN (
        SELECT ParentId, COUNT(*) AS AnswerCount
        FROM Posts
        WHERE PostTypeId = 2
        GROUP BY ParentId
    ) a ON p.Id = a.ParentId
    WHERE p.PostTypeId = 1
      AND p.Score >= 10
),
TagPopularity AS (
    -- expand TagList into rows using unnest/lateral; use safe check for NULL TagList
    SELECT t.Tag, COUNT(*) AS QuestionCount
    FROM TopQuestions q
    CROSS JOIN LATERAL (
      SELECT UNNEST(q.TagList) AS Tag
    ) t
    WHERE q.TagList IS NOT NULL
    GROUP BY t.Tag
),
RecentEdits AS (
    SELECT ph.PostId, ph.UserId, u.DisplayName, ph.PostHistoryTypeId, ph.CreationDate,
           ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS RN
    FROM PostHistory ph
    JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
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
SELECT ru.Id AS UserId,
       ru.DisplayName,
       ru.Reputation,
       ubs.TotalBadges,
       ubs.GoldBadges,
       ubs.SilverBadges,
       ubs.BronzeBadges,
       ubs.LastBadgeDate,
       q.Id AS QuestionId,
       q.Title,
       q.Score AS QuestionScore,
       q.ViewCount,
       q.AnswerCount,
       q.CreationDate AS QuestionCreationDate,
       CASE WHEN q.TagList IS NOT NULL THEN array_to_string(q.TagList, ', ') ELSE NULL END AS Tags,
       tp.Tag AS PopularTag,
       tp.QuestionCount AS PopularityOfTag,
       le.PostHistoryTypeId AS LastEditType,
       le.CreationDate AS LastEditDate,
       le.DisplayName AS LastEditorName,
       COALESCE(a.TotalAnswers, 0) AS TotalAnswersByUser,
       COALESCE(a.AvgAnswerScore, 0) AS AvgAnswerScoreByUser
FROM RecentHighRepUsers ru
LEFT JOIN UserBadgeStats ubs ON ru.Id = ubs.UserId
LEFT JOIN TopQuestions q ON q.OwnerUserId = ru.Id
LEFT JOIN TagPopularity tp ON tp.Tag = ANY(q.TagList)
LEFT JOIN LatestEditsPerPost le ON le.PostId = q.Id
LEFT JOIN AnswerStats a ON a.OwnerUserId = ru.Id
WHERE q.CreationDate >= DATE '2024-10-01' - INTERVAL '1' YEAR
ORDER BY ru.Reputation DESC, ubs.TotalBadges DESC, q.Score DESC, tp.QuestionCount DESC
LIMIT 100;