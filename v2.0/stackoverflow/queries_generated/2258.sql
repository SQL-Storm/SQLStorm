-- {"query": "2258.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1364} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        ARRAY[t.TagName] AS AncestorTags
    FROM Tags t
    WHERE NOT t.IsModeratorOnly = 1

    UNION ALL

    SELECT
        t.Id,
        t.TagName,
        t.Count,
        r.AncestorTags || t.TagName
    FROM Tags t
    JOIN RecursiveTagHierarchy r ON t.WikiPostId = r.Id
    WHERE NOT t.IsModeratorOnly = 1
),
UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsAsked,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersGiven,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1, 2)) AS AvgPostScore,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(p.CreationDate) AS LastPostDate,
        ROW_NUMBER() OVER (PARTITION BY u.Reputation ORDER BY u.CreationDate) AS RepRankForCreationOrder
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation > (
        SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY Reputation)
        FROM Users
    )
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
QuestionsWithAnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.Tags,
        q.CreationDate AS QuestionDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.OwnerUserId,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerDate,
        a.OwnerUserId AS AnswerOwnerUserId,
        u.DisplayName AS AnswerOwnerDisplayName,
        ROW_NUMBER() OVER (
            PARTITION BY q.Id
            ORDER BY a.Score DESC NULLS LAST, a.CreationDate ASC
        ) AS AnswerRank
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Users u ON u.Id = a.OwnerUserId
    WHERE q.PostTypeId = 1
      AND q.ClosedDate IS NULL
),
TopAnswers AS (
    SELECT *
    FROM QuestionsWithAnswerStats
    WHERE AnswerRank = 1
),
CloseReasonsSummary AS (
    SELECT
        crt.Name AS CloseReason,
        COUNT(ph.Id) AS CloseCount,
        AVG(julianday('now') - julianday(ph.CreationDate)) AS AvgDaysSinceClosed
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS INTEGER)
    WHERE ph.PostHistoryTypeId = 10 -- Post Closed
      AND ph.Comment ~ '^[0-9]+$' -- numeric close reason IDs only
    GROUP BY crt.Name
),
FinalFilteredUsers AS (
    SELECT
        ups.UserId,
        ups.DisplayName,
        ups.QuestionsAsked,
        ups.AnswersGiven,
        ups.TotalScore,
        ups.AvgPostScore,
        ups.BadgeCount,
        ups.GoldBadges,
        ups.SilverBadges,
        ups.BronzeBadges,
        ups.LastPostDate
    FROM UserPostStats ups
    WHERE ups.AnswersGiven > 5
      AND ups.TotalScore > 100
      AND ups.AvgPostScore IS NOT NULL
)
SELECT
    fdu.DisplayName,
    fdu.QuestionsAsked,
    fdu.AnswersGiven,
    fdu.TotalScore,
    fdu.AvgPostScore,
    fdu.BadgeCount,
    fdu.GoldBadges,
    fdu.SilverBadges,
    fdu.BronzeBadges,
    fdu.LastPostDate,
    ta.QuestionId,
    ta.Title,
    COALESCE(ta.Tags, '') AS Tags,
    ta.QuestionDate,
    ta.QuestionScore,
    ta.ViewCount,
    ta.AnswerId,
    ta.AnswerScore,
    ta.AnswerDate,
    ta.AnswerOwnerUserId,
    ta.AnswerOwnerDisplayName,
    crs.CloseReason,
    crs.CloseCount,
    crs.AvgDaysSinceClosed,
    CASE
        WHEN ta.Tags IS NOT NULL THEN
            array_to_string(
                array(
                    SELECT DISTINCT unnest(string_to_array(
                        replace(replace(replace(ta.Tags,'<',''),'>',''),'"',''), ' ')
                    )
                    ORDER BY 1
                ), ', '
            )
        ELSE ''
    END AS ParsedTags,
    ntile(10) OVER (ORDER BY fdu.TotalScore DESC) AS UserDecileByScore,
    CASE
        WHEN fdu.BadgeCount > 50 THEN 'Top Badged'
        WHEN fdu.BadgeCount BETWEEN 10 AND 50 THEN 'Medium Badged'
        ELSE 'Low Badged'
    END AS BadgeCategory,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = fdu.UserId) -
    (SELECT COUNT(*) FROM Comments c2 WHERE c2.UserId = fdu.UserId) AS PostsMinusCommentsDifference,
    (
        SELECT COUNT(*)
        FROM Votes v
        WHERE v.UserId = fdu.UserId
          AND v.VoteTypeId = 2 -- UpMod
          AND v.CreationDate > (NOW() - INTERVAL '1 year')
    ) AS RecentUpVotes
FROM FinalFilteredUsers fdu
LEFT JOIN TopAnswers ta ON ta.AnswerOwnerUserId = fdu.UserId
LEFT JOIN CloseReasonsSummary crs ON crs.CloseReason IS NOT NULL
ORDER BY fdu.TotalScore DESC NULLS LAST, ta.QuestionScore DESC NULLS LAST
LIMIT 100;
