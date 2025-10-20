WITH RankedPosts AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        u.Reputation AS OwnerReputation,
        u.DisplayName AS OwnerName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn,
        COUNT(*) OVER (PARTITION BY p.PostTypeId) AS TotalPosts
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1,2)
),
AcceptedAnswersText AS (
    SELECT
        q.Id AS QuestionId,
        a.Body AS AcceptedAnswerBody,
        SUBSTRING(a.Body FROM 1 FOR 200) AS AcceptedAnswerSnippet
    FROM Posts q
    LEFT JOIN Posts a ON q.AcceptedAnswerId = a.Id
    WHERE q.PostTypeId = 1
),
UserBadgeSummary AS (
    SELECT
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(Date) AS LatestBadgeDate
    FROM Badges
    GROUP BY UserId
),
PostCommentsCount AS (
    SELECT
        PostId,
        COUNT(*) AS CommentCountTotal,
        COUNT(CASE WHEN Score > 0 THEN 1 END) AS PositiveScoreComments,
        COUNT(CASE WHEN Score <= 0 OR Score IS NULL THEN 1 END) AS NonPositiveScoreComments
    FROM Comments
    GROUP BY PostId
),
FilteredPostHistory AS (
    SELECT ph.PostId, ph.PostHistoryTypeId, ph.CreationDate, ph.UserId,
           ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS Rnk
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
LatestEdits AS (
    SELECT fph.PostId, pht.Name AS EditType, fph.CreationDate, fph.UserId
    FROM FilteredPostHistory fph
    INNER JOIN PostHistoryTypes pht ON fph.PostHistoryTypeId = pht.Id
    WHERE fph.Rnk = 1
),
DuplicatesReasonCount AS (
    SELECT pl.PostId, COUNT(*) AS DuplicateCount
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3
    GROUP BY pl.PostId
),
DeviceOccurrence AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(u.Location, 'Unknown') AS LocationNormalized,
        CASE WHEN u.WebsiteUrl LIKE '%mobile%' THEN 1 ELSE 0 END AS MobileSiteVisitors,
        CASE WHEN u.Location IS NULL THEN 1 ELSE 0 END AS NullLocationFlag
    FROM Users u
    WHERE u.CreationDate < (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
),
QuestionsWithDuplicatesAndComments AS (
    SELECT
        rp.Id AS QuestionId,
        rp.Score AS QuestionScore,
        rp.ViewCount,
        COALESCE(dc.DuplicateCount, 0) AS DuplicateCount,
        COALESCE(pcc.CommentCountTotal, 0) AS TotalComments,
        COALESCE(pcc.PositiveScoreComments, 0) AS PositiveComments,
        COALESCE(pcc.NonPositiveScoreComments, 0) AS NonPositiveComments,
        COALESCE(aat.AcceptedAnswerSnippet, '') AS AcceptedAnswerSample,
        COALESCE(ub.GoldBadges, 0) AS GoldBadges,
        COALESCE(ub.SilverBadges, 0) AS SilverBadges,
        COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - rp.CreationDate))/86400 AS DaysSinceCreation
    FROM RankedPosts rp
    LEFT JOIN DuplicatesReasonCount dc ON rp.Id = dc.PostId
    LEFT JOIN PostCommentsCount pcc ON rp.Id = pcc.PostId
    LEFT JOIN AcceptedAnswersText aat ON rp.Id = aat.QuestionId
    LEFT JOIN UserBadgeSummary ub ON rp.OwnerUserId = ub.UserId
    WHERE rp.PostTypeId = 1
),
HighActivityUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS NumberOfPosts,
        AVG(p.Score) AS AvgPostScore,
        SUM(COALESCE(p.Score, 0)) AS TotalScore,
        SUM(COALESCE(v.PosUpVotes,0)) AS TotalUpVotes,
        SUM(COALESCE(v.TotVotes,0)-COALESCE(v.PosUpVotes,0)) AS OtherVotesCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1,2)
    LEFT JOIN (
        SELECT Vote.PostId,
               COUNT(*) AS TotVotes,
               COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS PosUpVotes
        FROM Votes Vote
        JOIN VoteTypes vt ON Vote.VoteTypeId = vt.Id
        GROUP BY Vote.PostId
    ) v ON p.Id = v.PostId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) > 5
),
CorrelatedBadges AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadgeCount,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadgeCount,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadgeCount,
        (SELECT MIN(Date) FROM Badges b WHERE b.UserId = u.Id) AS FirstBadgeDate
    FROM Users u
    WHERE u.Reputation > 5000
),
CombinedActiveQuestionsAndUsers AS (
    SELECT
        q.QuestionId,
        q.QuestionScore,
        q.ViewCount,
        q.DuplicateCount,
        q.TotalComments,
        q.PositiveComments,
        q.NonPositiveComments,
        q.AcceptedAnswerSample,
        q.GoldBadges,
        q.SilverBadges,
        q.BronzeBadges,
        q.DaysSinceCreation,
        hu.UserId,
        hu.DisplayName AS HighRepUserName,
        hu.NumberOfPosts,
        hu.AvgPostScore,
        hu.TotalScore
    FROM QuestionsWithDuplicatesAndComments q
    LEFT JOIN LATERAL (
        SELECT hu.UserId, hu.DisplayName, hu.NumberOfPosts, hu.AvgPostScore, hu.TotalScore
        FROM HighActivityUsers hu 
        WHERE hu.UserId = q.GoldBadges
           OR CAST(hu.NumberOfPosts AS integer) = q.BronzeBadges
        ORDER BY hu.TotalScore DESC LIMIT 1
    ) hu ON TRUE
),
TopQuestions AS (
    SELECT 
        c.QuestionId,
        SUBSTRING(c.AcceptedAnswerSample FROM 1 FOR 100) || '...' AS AcceptedAnswerPreview,
        c.QuestionScore,
        c.ViewCount,
        c.DuplicateCount,
        c.TotalComments,
        c.PositiveComments,
        c.NonPositiveComments,
        c.GoldBadges,
        c.SilverBadges,
        c.BronzeBadges,
        ROUND(c.DaysSinceCreation, 1) AS DaysOld,
        c.HighRepUserName,
        c.NumberOfPosts AS HighRepUserPostCount,
        ROUND(c.AvgPostScore, 2) AS HighRepUserAvgPostScore,
        c.TotalScore AS HighRepUserTotalScore
    FROM CombinedActiveQuestionsAndUsers c
    WHERE c.QuestionScore > (
        SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY Score) FROM Posts WHERE PostTypeId = 1
    ) AND c.TotalComments > 5
    ORDER BY c.QuestionScore DESC, c.ViewCount DESC
    LIMIT 50
),
RecentNegativeQuestions AS (
    SELECT
        p.Id AS QuestionId,
        '' AS AcceptedAnswerPreview,
        p.Score AS QuestionScore,
        p.ViewCount,
        0 AS DuplicateCount,
        0 AS TotalComments,
        0 AS PositiveComments,
        0 AS NonPositiveComments,
        0 AS GoldBadges,
        0 AS SilverBadges,
        0 AS BronzeBadges,
        0 AS DaysOld,
        NULL AS HighRepUserName,
        0 AS HighRepUserPostCount,
        CAST(0 AS numeric) AS HighRepUserAvgPostScore,
        0 AS HighRepUserTotalScore
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Score < 0
      AND p.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 month')
    ORDER BY p.Score ASC
    LIMIT 10
)
SELECT * FROM TopQuestions
UNION ALL
SELECT * FROM RecentNegativeQuestions
ORDER BY QuestionScore ASC NULLS LAST, ViewCount DESC NULLS LAST;