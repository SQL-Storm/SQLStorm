WITH 
RecentActiveQuestions AS (
    SELECT p.Id AS QuestionId, p.Title, p.OwnerUserId, p.Score, p.ViewCount, p.Tags,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserRecentRank
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate > DATE '2024-10-01' - INTERVAL '180' DAY
      AND p.AnswerCount >= 2
      AND p.ClosedDate IS NULL
),
UserBadgeSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COALESCE((SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1 AND b.Date > DATE '2024-10-01' - INTERVAL '365' DAY),0) AS GoldBadgesLastYear,
        COALESCE((SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2 AND b.Date > DATE '2024-10-01' - INTERVAL '365' DAY),0) AS SilverBadgesLastYear,
        COALESCE((SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3 AND b.Date > DATE '2024-10-01' - INTERVAL '365' DAY),0) AS BronzeBadgesLastYear,
        u.Reputation,
        u.CreationDate
    FROM Users u
    WHERE u.Reputation > 1000
),
AnswerStats AS (
    SELECT a.ParentId AS QuestionId,
           a.Id AS AnswerId,
           a.OwnerUserId AS AnswerOwnerId,
           a.Score AS AnswerScore,
           LENGTH(COALESCE(a.Body,'')) AS AnswerBodyLength,
           (LENGTH(COALESCE(a.Body,'')) - LENGTH(REPLACE(COALESCE(a.Body,''), ':)', ''))) AS AnswerSmileyCount,
           RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC) AS AnswerRankByScore
    FROM Posts a
    WHERE a.PostTypeId = 2
),
PostCommentSummary AS (
    SELECT p.Id AS PostId, p.PostTypeId,
           COUNT(c.Id) AS TotalComments,
           SUM(CASE WHEN c.Score IS NULL THEN 0 ELSE c.Score END) AS SumCommentScores,
           MAX(c.CreationDate) AS LatestCommentDate
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    GROUP BY p.Id, p.PostTypeId
),
PostLinkInfo AS (
    SELECT pl.PostId, pl.RelatedPostId, lt.Name AS LinkTypeName, pl.CreationDate AS LinkCreationDate,
           p.Title AS PostTitle, rp.Title AS RelatedPostTitle
    FROM PostLinks pl
    INNER JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    LEFT JOIN Posts p ON p.Id = pl.PostId
    LEFT JOIN Posts rp ON rp.Id = pl.RelatedPostId
),
UserActivityWindows AS (
    SELECT u.Id, u.DisplayName,
           EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate))/86400 AS DaysAlive,
           RANK() OVER (ORDER BY u.Reputation DESC) AS RepRank,
           ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS RankInLocation,
           COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadgeCount,
           COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadgeCount,
           COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadgeCount
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id AND b.Date > DATE '2024-10-01' - INTERVAL '730' DAY
    GROUP BY u.Id, u.DisplayName, u.LastAccessDate, u.CreationDate, u.Reputation, u.Location
)
SELECT 
    raq.QuestionId,
    raq.Title AS QuestionTitle,
    raq.Tags,
    us.DisplayName AS QuestionOwner,
    us.Reputation AS OwnerReputation,
    us.GoldBadgesLastYear,
    us.SilverBadgesLastYear,
    us.BronzeBadgesLastYear,
    raq.Score AS QuestionScore,
    raq.ViewCount AS QuestionViewCount,
    assoc.AnswerId,
    assoc.AnswerScore,
    ua.DisplayName AS AnswerOwnerName,
    ua.Reputation AS AnswerOwnerReputation,
    assoc.AnswerBodyLength,
    assoc.AnswerSmileyCount,
    pcs.TotalComments,
    pcs.SumCommentScores,
    pls.CountRelatedLinks,
    pls.DuplicateLinks,
    uaActivity.DaysAlive,
    uaActivity.RepRank,
    uaActivity.RankInLocation,
    uaActivity.GoldBadgeCount,
    uaActivity.SilverBadgeCount,
    uaActivity.BronzeBadgeCount
FROM RecentActiveQuestions raq
INNER JOIN UserBadgeSummary us ON us.UserId = raq.OwnerUserId
INNER JOIN AnswerStats assoc ON assoc.QuestionId = raq.QuestionId AND assoc.AnswerRankByScore = 1
LEFT JOIN Users ua ON ua.Id = assoc.AnswerOwnerId
LEFT JOIN UserActivityWindows uaActivity ON uaActivity.Id = ua.Id
LEFT JOIN PostCommentSummary pcs ON pcs.PostId = raq.QuestionId
LEFT JOIN (
    SELECT pl.PostId, 
           COUNT(*) AS CountRelatedLinks,
           SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateLinks
    FROM PostLinks pl
    GROUP BY pl.PostId
) pls ON pls.PostId = raq.QuestionId
WHERE
    raq.UserRecentRank <= 5
    AND (
         raq.Tags IS NOT NULL 
         AND EXISTS (
             SELECT 1
             FROM (
               SELECT UNNEST(STRING_TO_ARRAY(TRIM(BOTH '<>' FROM raq.Tags), '><')) AS tag
             ) t
             WHERE LOWER(t.tag) LIKE 'sql%'
         )
    )
ORDER BY us.Reputation DESC, raq.Score DESC, assoc.AnswerScore DESC
LIMIT 50;