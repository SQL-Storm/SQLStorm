WITH RECURSIVE RecursiveCTE AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS rn,
        1 AS level
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL

    UNION ALL

    SELECT 
        p2.Id,
        p2.PostTypeId,
        p2.OwnerUserId,
        p2.CreationDate,
        p2.Title,
        p2.Score,
        p2.ViewCount,
        p2.Tags,
        rc.rn + 1,
        rc.level + 1
    FROM Posts p2
    JOIN RecursiveCTE rc ON rc.OwnerUserId = p2.OwnerUserId AND p2.CreationDate > rc.CreationDate
    WHERE p2.PostTypeId = 1 AND p2.OwnerUserId IS NOT NULL AND rc.level < 3
),
UserBadgeCounts AS (
    SELECT 
        b.UserId,
        b.Class,
        COUNT(*) AS BadgeCount
    FROM Badges b
    GROUP BY b.UserId, b.Class
),
UserReputationWindow AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate,
        u.DisplayName,
        COALESCE(ubc_gold.BadgeCount, 0) AS GoldBadges,
        COALESCE(ubc_silver.BadgeCount, 0) AS SilverBadges,
        COALESCE(ubc_bronze.BadgeCount, 0) AS BronzeBadges,
        AVG(p.Score) OVER (PARTITION BY u.Id ORDER BY u.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS AvgScoreUpToNow
    FROM Users u
    LEFT JOIN UserBadgeCounts ubc_gold ON ubc_gold.UserId = u.Id AND ubc_gold.Class = 1
    LEFT JOIN UserBadgeCounts ubc_silver ON ubc_silver.UserId = u.Id AND ubc_silver.Class = 2
    LEFT JOIN UserBadgeCounts ubc_bronze ON ubc_bronze.UserId = u.Id AND ubc_bronze.Class = 3
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
),
CloseReasonUsage AS (
    SELECT 
        crt.Id AS CloseReasonId,
        crt.Name AS CloseReasonName,
        COUNT(ph.Id) AS CloseCount
    FROM CloseReasonTypes crt
    LEFT JOIN PostHistory ph ON ph.PostHistoryTypeId = 10 AND ph.Comment = CAST(crt.Id AS VARCHAR)
    GROUP BY crt.Id, crt.Name
),
Duplicates AS (
    SELECT DISTINCT pl.PostId
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3
),
QuestionsWithAnswers AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate,
        q.OwnerUserId,
        COUNT(a.Id) AS AnswerCount,
        MAX(a.Score) AS MaxAnswerScore,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesCount,
        STRING_AGG(DISTINCT u.DisplayName, ', ') AS Answerers
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Votes v ON v.PostId = a.Id AND v.VoteTypeId IN (2,3)
    LEFT JOIN Users u ON u.Id = a.OwnerUserId
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.CreationDate, q.OwnerUserId
),
ComplexFilteredQuestions AS (
    SELECT 
        qwa.QuestionId,
        qwa.Title,
        urw.DisplayName,
        qwa.AnswerCount,
        qwa.MaxAnswerScore,
        qwa.UpVotesCount,
        qwa.DownVotesCount,
        urw.GoldBadges,
        urw.SilverBadges,
        urw.BronzeBadges,
        urw.AvgScoreUpToNow,
        cr.CloseReasonName,
        CASE WHEN d.PostId IS NOT NULL THEN 1 ELSE 0 END AS IsDuplicate,
        qwa.OwnerUserId,
        urw.Reputation
    FROM QuestionsWithAnswers qwa
    JOIN UserReputationWindow urw ON urw.UserId = qwa.OwnerUserId
    LEFT JOIN PostHistory ph ON ph.PostId = qwa.QuestionId AND ph.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS SMALLINT)
    LEFT JOIN CloseReasonUsage cr ON cr.CloseReasonId = crt.Id
    LEFT JOIN Duplicates d ON d.PostId = qwa.QuestionId
    WHERE 
        (qwa.AnswerCount > 2 OR qwa.MaxAnswerScore > 5) 
        AND urw.Reputation > 1000
        AND (qwa.Title ILIKE '%performance%' OR qwa.Title ILIKE '%benchmark%')
        AND (cr.CloseReasonName IS NULL OR cr.CloseReasonName <> 'Duplicate')
        AND (d.PostId IS NULL)
)
SELECT 
    cfq.QuestionId,
    cfq.Title,
    cfq.DisplayName AS OwnerName,
    cfq.AnswerCount,
    cfq.MaxAnswerScore,
    cfq.UpVotesCount,
    cfq.DownVotesCount,
    cfq.GoldBadges,
    cfq.SilverBadges,
    cfq.BronzeBadges,
    cfq.AvgScoreUpToNow,
    COALESCE(cru.CloseCount, 0) AS TotalClosed,
    CASE WHEN cfq.IsDuplicate = 1 THEN 'Yes' ELSE 'No' END AS DuplicateFlag,
    SUBSTRING(CAST(CAST(cfq.QuestionId AS BIGINT) * RANDOM() AS TEXT), 1, 15) AS RandomStr,
    CASE WHEN cfq.UpVotesCount > cfq.DownVotesCount THEN 'Positive' ELSE 'NegativeOrNeutral' END AS VoteSentiment
FROM ComplexFilteredQuestions cfq
LEFT JOIN CloseReasonUsage cru ON cru.CloseReasonName = cfq.CloseReasonName
ORDER BY cfq.AvgScoreUpToNow DESC, cfq.MaxAnswerScore DESC
LIMIT 100;