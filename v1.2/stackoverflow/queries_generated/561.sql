-- {"query": "561.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2148} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        ARRAY[t.TagName] AS TagPath
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT
        child.Id,
        child.TagName,
        child.Count,
        child.ExcerptPostId,
        child.WikiPostId,
        child.IsModeratorOnly,
        child.IsRequired,
        parent.TagPath || child.TagName
    FROM Tags child
    JOIN RecursiveTagHierarchy parent ON child.Id <> parent.Id
    WHERE child.IsRequired = 1 AND NOT child.TagName = ANY(parent.TagPath)
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        b.Class,
        COUNT(*) AS BadgeCount
    FROM Badges b
    WHERE b.Date > NOW() - INTERVAL '1 year'
    GROUP BY b.UserId, b.Class
),
UserActivity AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COALESCE(ubc_gold.BadgeCount, 0) AS GoldBadges,
        COALESCE(ubc_silver.BadgeCount, 0) AS SilverBadges,
        COALESCE(ubc_bronze.BadgeCount, 0) AS BronzeBadges,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsAsked,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersGiven,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgPostScore,
        MAX(p.LastActivityDate) AS LastPostActivity
    FROM Users u
    LEFT JOIN UserBadgeCounts ubc_gold ON u.Id = ubc_gold.UserId AND ubc_gold.Class = 1
    LEFT JOIN UserBadgeCounts ubc_silver ON u.Id = ubc_silver.UserId AND ubc_silver.Class = 2
    LEFT JOIN UserBadgeCounts ubc_bronze ON u.Id = ubc_bronze.UserId AND ubc_bronze.Class = 3
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, ubc_gold.BadgeCount, ubc_silver.BadgeCount, ubc_bronze.BadgeCount
),
TopQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CreationDate,
        p.Tags,
        u.DisplayName AS OwnerName,
        RANK() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS RankByScore
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate > NOW() - INTERVAL '1 year'
),
QuestionWithAcceptedAnswer AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.CreationDate,
        q.Tags,
        q.OwnerName,
        a.Id AS AcceptedAnswerId,
        a.Score AS AcceptedAnswerScore,
        a.CreationDate AS AcceptedAnswerCreationDate,
        a.OwnerUserId AS AcceptedAnswerOwnerId,
        au.DisplayName AS AcceptedAnswerOwnerName
    FROM TopQuestions q
    LEFT JOIN Posts a ON q.AcceptedAnswerId = a.Id
    LEFT JOIN Users au ON a.OwnerUserId = au.Id
),
PostHistoryCloseReasons AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReasonName,
        ph.CreationDate AS CloseDate
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON CAST(ph.Comment AS INT) = crt.Id
    WHERE ph.PostHistoryTypeId = 10
),
QuestionCloseInfo AS (
    SELECT
        q.QuestionId,
        q.Title,
        q.OwnerUserId,
        q.QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.CreationDate,
        q.Tags,
        q.OwnerName,
        pcr.CloseReasonName,
        pcr.CloseDate
    FROM QuestionWithAcceptedAnswer q
    LEFT JOIN PostHistoryCloseReasons pcr ON q.QuestionId = pcr.PostId
),
VotesSummary AS (
    SELECT
        p.Id AS PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS Favorites
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.Id
),
UserPostScores AS (
    SELECT
        p.OwnerUserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionsCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswersCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgScore,
        MAX(p.Score) AS MaxScore
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserRankedByScore AS (
    SELECT
        ups.OwnerUserId,
        ups.QuestionsCount,
        ups.AnswersCount,
        ups.TotalScore,
        ups.AvgScore,
        ups.MaxScore,
        RANK() OVER (ORDER BY ups.TotalScore DESC NULLS LAST) AS ScoreRank
    FROM UserPostScores ups
),
FinalResult AS (
    SELECT
        qci.QuestionId,
        qci.Title,
        qci.OwnerUserId,
        ua.DisplayName AS QuestionOwnerName,
        qci.QuestionScore,
        qci.ViewCount,
        qci.AnswerCount,
        qci.CreationDate AS QuestionCreationDate,
        qci.Tags,
        qci.CloseReasonName,
        qci.CloseDate,
        qwa.AcceptedAnswerId,
        qwa.AcceptedAnswerScore,
        qwa.AcceptedAnswerCreationDate,
        qwa.AcceptedAnswerOwnerId,
        aou.DisplayName AS AcceptedAnswerOwnerName,
        vs.UpVotes,
        vs.DownVotes,
        vs.Favorites,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.Reputation,
        ua.LastAccessDate,
        urbs.ScoreRank,
        ua.QuestionsAsked,
        ua.AnswersGiven,
        ua.AvgPostScore,
        ua.LastPostActivity,
        -- Complex string expression concatenating tags and badges info
        CONCAT_WS(' | ',
            qci.Tags,
            CONCAT('Badges(Gold/Silver/Bronze): ', ua.GoldBadges, '/', ua.SilverBadges, '/', ua.BronzeBadges),
            CONCAT('UserRank: #', urbs.ScoreRank),
            CONCAT('CloseReason: ', COALESCE(qci.CloseReasonName, 'Open'))
        ) AS SummaryInfo
    FROM QuestionCloseInfo qci
    LEFT JOIN QuestionWithAcceptedAnswer qwa ON qci.QuestionId = qwa.QuestionId
    LEFT JOIN Users ua ON qci.OwnerUserId = ua.Id
    LEFT JOIN Users aou ON qwa.AcceptedAnswerOwnerId = aou.Id
    LEFT JOIN VotesSummary vs ON qci.QuestionId = vs.PostId
    LEFT JOIN UserActivity ua2 ON qci.OwnerUserId = ua2.Id
    LEFT JOIN UserRankedByScore urbs ON qci.OwnerUserId = urbs.OwnerUserId
    LEFT JOIN UserActivity ua ON qci.OwnerUserId = ua.Id
    ORDER BY qci.QuestionScore DESC NULLS LAST, qci.ViewCount DESC NULLS LAST
    LIMIT 100
)
SELECT *
FROM FinalResult
WHERE (CloseReasonName IS NULL OR CloseReasonName NOT IN ('Duplicate', 'Off-topic'))
  AND QuestionCreationDate >= NOW() - INTERVAL '6 months'
  AND (AcceptedAnswerScore IS NULL OR AcceptedAnswerScore > 5)
  AND (ua.Reputation > 1000 OR ua.GoldBadges > 0)
UNION
SELECT
    p.Id AS QuestionId,
    p.Title,
    p.OwnerUserId,
    u.DisplayName AS QuestionOwnerName,
    p.Score AS QuestionScore,
    p.ViewCount,
    p.AnswerCount,
    p.CreationDate AS QuestionCreationDate,
    p.Tags,
    NULL AS CloseReasonName,
    NULL AS CloseDate,
    NULL AS AcceptedAnswerId,
    NULL AS AcceptedAnswerScore,
    NULL AS AcceptedAnswerCreationDate,
    NULL AS AcceptedAnswerOwnerId,
    NULL AS AcceptedAnswerOwnerName,
    vs.UpVotes,
    vs.DownVotes,
    vs.Favorites,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    u.Reputation,
    u.LastAccessDate,
    NULL AS ScoreRank,
    0 AS QuestionsAsked,
    0 AS AnswersGiven,
    NULL AS AvgPostScore,
    NULL AS LastPostActivity,
    CONCAT_WS(' | ',
        p.Tags,
        'No accepted answer or low score',
        CONCAT('UserRep: ', u.Reputation)
    ) AS SummaryInfo
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN VotesSummary vs ON p.Id = vs.PostId
WHERE p.PostTypeId = 1
  AND p.CreationDate >= NOW() - INTERVAL '6 months'
  AND p.AcceptedAnswerId IS NULL
  AND p.Score > 50
ORDER BY QuestionScore DESC NULLS LAST, ViewCount DESC NULLS LAST
LIMIT 50;
