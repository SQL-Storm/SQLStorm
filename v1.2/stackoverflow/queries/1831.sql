WITH TopQuestionBadges AS (
    SELECT u.Id AS UserId,
           u.DisplayName,
           b.Name AS BadgeName,
           b.Class,
           (
               SELECT COUNT(*)
               FROM Posts p
               WHERE p.OwnerUserId = u.Id
                 AND p.PostTypeId = 1
                 AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
                 AND p.Score >= 10
           ) AS QualifiedQuestions,
           ROW_NUMBER() OVER (PARTITION BY b.Class ORDER BY (
               SELECT COUNT(*)
               FROM Posts p2
               WHERE p2.OwnerUserId = u.Id
                 AND p2.PostTypeId = 1
                 AND p2.Score >= 10
             ) DESC, u.Reputation DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE b.Class IN (1, 2, 3)
),
UserQuestionsMatter AS (
    SELECT p.Id, p.OwnerUserId, p.CreationDate, p.Tags,
           LENGTH(COALESCE(p.Body, '')) AS BodyLength,
           p.AnswerCount,
           p.ViewCount,
           LEAST(GREATEST(p.Score, 0), 5) AS CrutchedScore,
           ROW_NUMBER() OVER (
               PARTITION BY p.OwnerUserId 
               ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
           ) AS RowNum
    FROM Posts p
    WHERE p.PostTypeId = 1 
      AND p.Score IS NOT NULL
)
SELECT t.UserId,
       t.DisplayName,
       t.BadgeName,
       t.Class,
       t.QualifiedQuestions,
       t.BadgeRank,
       uqm.Id AS PostId,
       uqm.CreationDate,
       uqm.Tags,
       uqm.BodyLength,
       uqm.AnswerCount,
       uqm.ViewCount,
       uqm.CrutchedScore,
       uqm.RowNum
FROM TopQuestionBadges t
JOIN UserQuestionsMatter uqm
  ON uqm.OwnerUserId = t.UserId
WHERE uqm.RowNum = 1
  AND t.QualifiedQuestions > 0
ORDER BY t.Class, t.BadgeRank;