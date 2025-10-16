-- {"query": "261.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1931} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 AS Level,
        ARRAY[t.TagName] AS Path
    FROM Tags t
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0

    UNION ALL

    SELECT
        child.Id,
        child.TagName,
        child.Count,
        child.ExcerptPostId,
        child.WikiPostId,
        parent.Level + 1,
        parent.Path || child.TagName
    FROM Tags child
    JOIN RecursiveTagHierarchy parent ON child.Id > parent.Id AND child.IsModeratorOnly = 0
    WHERE NOT child.TagName = ANY(parent.Path)
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsAsked,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersGiven,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        COUNT(DISTINCT b.Id) AS BadgesEarned,
        COALESCE(SUM(v.BountyAmount), 0) AS TotalBountyGiven,
        MAX(p.CreationDate) AS LastPostDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate) AS ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id AND v.VoteTypeId IN (8,9) -- BountyStart and BountyClose
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostDetails AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.ParentId,
        u.DisplayName AS OwnerName,
        ph.PostHistoryTypeId,
        ph.CreationDate AS HistoryDate,
        ph.UserId AS EditorUserId,
        ph.Comment AS CloseReason,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY ph.CreationDate DESC) AS LatestHistoryRank
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10,11) -- Closed or Reopened
),
TopQuestionsWithAnswers AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate AS QuestionDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.Tags,
        q.OwnerUserId,
        u.DisplayName AS QuestionOwner,
        a.Id AS AnswerId,
        a.CreationDate AS AnswerDate,
        a.Score AS AnswerScore,
        a.OwnerUserId AS AnswerOwnerUserId,
        au.DisplayName AS AnswerOwner,
        a.ParentId,
        a.AcceptedAnswerId,
        ph.CloseReason,
        ph.HistoryDate AS CloseDate
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Users u ON u.Id = q.OwnerUserId
    LEFT JOIN Users au ON au.Id = a.OwnerUserId
    LEFT JOIN PostHistory ph ON ph.PostId = q.Id AND ph.PostHistoryTypeId = 10 -- Post Closed
    WHERE q.PostTypeId = 1
      AND q.Score > 10
      AND q.ViewCount > 1000
),
AnswerRanks AS (
    SELECT
        a.QuestionId,
        a.AnswerId,
        a.AnswerScore,
        RANK() OVER (PARTITION BY a.QuestionId ORDER BY a.AnswerScore DESC, a.AnswerDate ASC) AS AnswerRank
    FROM TopQuestionsWithAnswers a
),
FilteredAnswers AS (
    SELECT
        ar.QuestionId,
        ar.AnswerId,
        ar.AnswerScore,
        ar.AnswerRank
    FROM AnswerRanks ar
    WHERE ar.AnswerRank <= 3
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(DISTINCT b.Name) AS DistinctBadges
    FROM Badges b
    GROUP BY b.UserId
),
ComplexUserStats AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionsAsked,
        ua.AnswersGiven,
        ua.CommentsMade,
        ua.BadgesEarned,
        ua.TotalBountyGiven,
        COALESCE(ubs.GoldBadges,0) AS GoldBadges,
        COALESCE(ubs.SilverBadges,0) AS SilverBadges,
        COALESCE(ubs.BronzeBadges,0) AS BronzeBadges,
        COALESCE(ubs.DistinctBadges,0) AS DistinctBadges,
        ua.LastPostDate,
        ua.ReputationRank,
        CASE
            WHEN ua.ReputationRank <= 10 THEN 'Top 10'
            WHEN ua.ReputationRank <= 100 THEN 'Top 100'
            ELSE 'Other'
        END AS ReputationTier,
        CASE
            WHEN ua.TotalBountyGiven > 10000 THEN 'High Spender'
            WHEN ua.TotalBountyGiven BETWEEN 1000 AND 10000 THEN 'Medium Spender'
            ELSE 'Low Spender'
        END AS BountySpendingCategory
    FROM UserActivity ua
    LEFT JOIN UserBadgeSummary ubs ON ubs.UserId = ua.UserId
),
FinalResult AS (
    SELECT
        q.QuestionId,
        q.Title,
        q.QuestionDate,
        q.QuestionScore,
        q.ViewCount,
        q.Tags,
        q.QuestionOwner,
        f.AnswerId,
        f.AnswerScore,
        a.OwnerUserId AS AnswerOwnerUserId,
        au.DisplayName AS AnswerOwner,
        q.CloseReason,
        q.CloseDate,
        cus.DisplayName AS AnswerOwnerDisplayName,
        cus.Reputation AS AnswerOwnerReputation,
        cus.GoldBadges,
        cus.SilverBadges,
        cus.BronzeBadges,
        cus.DistinctBadges,
        cus.ReputationTier,
        cus.BountySpendingCategory,
        STRING_AGG(DISTINCT ph.Name, ', ') FILTER (WHERE ph.Id IS NOT NULL) AS PostHistoryTypesInvolved
    FROM FilteredAnswers f
    JOIN TopQuestionsWithAnswers q ON q.AnswerId = f.AnswerId
    JOIN Posts a ON a.Id = f.AnswerId
    LEFT JOIN Users au ON au.Id = a.OwnerUserId
    LEFT JOIN ComplexUserStats cus ON cus.UserId = a.OwnerUserId
    LEFT JOIN PostHistory ph ON ph.PostId = q.QuestionId
    GROUP BY
        q.QuestionId, q.Title, q.QuestionDate, q.QuestionScore, q.ViewCount, q.Tags, q.QuestionOwner,
        f.AnswerId, f.AnswerScore, a.OwnerUserId, au.DisplayName, q.CloseReason, q.CloseDate,
        cus.DisplayName, cus.Reputation, cus.GoldBadges, cus.SilverBadges, cus.BronzeBadges, cus.DistinctBadges,
        cus.ReputationTier, cus.BountySpendingCategory
)
SELECT
    fr.QuestionId,
    fr.Title,
    fr.QuestionDate,
    fr.QuestionScore,
    fr.ViewCount,
    fr.Tags,
    fr.QuestionOwner,
    fr.AnswerId,
    fr.AnswerScore,
    fr.AnswerOwnerUserId,
    fr.AnswerOwner,
    fr.CloseReason,
    fr.CloseDate,
    fr.AnswerOwnerDisplayName,
    fr.ReputationTier,
    fr.BountySpendingCategory,
    fr.GoldBadges,
    fr.SilverBadges,
    fr.BronzeBadges,
    fr.DistinctBadges,
    fr.PostHistoryTypesInvolved,
    LENGTH(fr.Title) + COALESCE(NULLIF(fr.Tags, ''), '')::text_length AS TitleTagLengthSum,
    CASE
        WHEN fr.CloseReason IS NOT NULL THEN 'Closed'
        ELSE 'Open'
    END AS PostStatus,
    CASE
        WHEN fr.AnswerScore > fr.QuestionScore THEN 'Answer Outperforms Question'
        ELSE 'Question Outperforms Answer'
    END AS PerformanceComparison
FROM FinalResult fr
WHERE fr.QuestionDate > CURRENT_DATE - INTERVAL '1 year'
ORDER BY fr.QuestionScore DESC, fr.AnswerScore DESC, fr.ViewCount DESC
LIMIT 50;
