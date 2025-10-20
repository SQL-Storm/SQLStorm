-- {"query": "1240.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1373} 
WITH 
-- Filter recently active questions with at least 2 answers
RecentActiveQuestions AS (
    SELECT p.Id AS QuestionId, p.Title, p.OwnerUserId, p.Score, p.ViewCount, p.Tags,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserRecentRank
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate > cast('2024-10-01' as date) - INTERVAL '180 days'
      AND p.AnswerCount >= 2
      AND p.ClosedDate IS NULL
),
-- Aggregate badge counts by user and badge class in last year using correlated subqueries
UserBadgeSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COALESCE((SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1 AND b.Date > cast('2024-10-01' as date) - INTERVAL '365 days'),0) AS GoldBadgesLastYear,
        COALESCE((SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2 AND b.Date > cast('2024-10-01' as date) - INTERVAL '365 days'),0) AS SilverBadgesLastYear,
        COALESCE((SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3 AND b.Date > cast('2024-10-01' as date) - INTERVAL '365 days'),0) AS BronzeBadgesLastYear,
        u.Reputation,
        u.CreationDate
    FROM Users u
    WHERE u.Reputation > 1000
),
-- Answer stats, including smiley count in body and text length, deduplicated with DISTINCT ON
AnswerStats AS (
    SELECT DISTINCT ON (a.ParentId) a.ParentId AS QuestionId,
           a.Id AS AnswerId,
           a.OwnerUserId AS AnswerOwnerId,
           a.Score AS AnswerScore,
           LENGTH(coalesce(a.Body,'')) AS AnswerBodyLength,
           (LENGTH(coalesce(a.Body,'')) - LENGTH(REPLACE(coalesce(a.Body,''), ':)', ''))) AS AnswerSmileyCount,
           RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC) AS AnswerRankByScore
    FROM Posts a
    WHERE a.PostTypeId = 2
),
-- Number of comments per post with conditional NULL logic for score
PostCommentSummary AS (
    SELECT p.Id AS PostId, p.PostTypeId,
           COUNT(c.Id) AS TotalComments,
           SUM(CASE WHEN c.Score IS NULL THEN 0 ELSE c.Score END) AS SumCommentScores,
           MAX(c.CreationDate) AS LatestCommentDate
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    GROUP BY p.Id, p.PostTypeId
),
-- Combine linking info about posts and related posts (both directions) with outer joins and COALESCE
PostLinkInfo AS (
    SELECT pl.PostId, pl.RelatedPostId, lt.Name AS LinkTypeName, pl.CreationDate AS LinkCreationDate,
           p.Title AS PostTitle, rp.Title AS RelatedPostTitle
    FROM PostLinks pl
    INNER JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    LEFT JOIN Posts p ON p.Id = pl.PostId
    LEFT JOIN Posts rp ON rp.Id = pl.RelatedPostId
),
-- Compute user activity windows and last access age
UserActivityWindows AS (
    SELECT u.Id, u.DisplayName,
           EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate))/86400 AS DaysAlive,
           RANK() OVER (ORDER BY u.Reputation DESC) AS RepRank,
           ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS RankInLocation,
           COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadgeCount,
           COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadgeCount,
           COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadgeCount
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id AND b.Date > cast('2024-10-01' as date) - INTERVAL '730 days'
    GROUP BY u.Id, u.DisplayName, u.LastAccessDate, u.CreationDate
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
         -- Complex tag substring and NULL logic in Tags string (simulate XML path searching on tags)
         raq.Tags IS NOT NULL 
         AND EXISTS (
             SELECT 1 FROM UNNEST(string_to_array(trim(both '<>' FROM raq.Tags), '><')) AS tag
             WHERE LOWER(tag) LIKE 'sql%'
         )
    )
ORDER BY us.Reputation DESC, raq.Score DESC, assoc.AnswerScore DESC
LIMIT 50;