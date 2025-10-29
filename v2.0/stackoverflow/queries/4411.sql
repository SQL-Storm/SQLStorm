-- {"query": "4411.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1631}
WITH RankedUserPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
),
UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT rup.PostId) AS TotalQuestions,
        SUM(rup.PostScore) AS TotalQuestionScore,
        AVG(EXTRACT(EPOCH FROM (rup.PostCreationDate - u.CreationDate)) / 86400.0) AS AvgDaysToFirstQuestion,
        MAX(EXTRACT(EPOCH FROM (rup.PostCreationDate - u.CreationDate)) / 86400.0) AS MaxDaysToFirstQuestion,
        (
            SELECT COUNT(*)
            FROM PostHistory ph
            WHERE ph.UserId = u.Id
              AND ph.PostHistoryTypeId IN (4, 5, 6)
        ) AS EditCount,
        (
            SELECT COUNT(DISTINCT v.PostId)
            FROM Votes v
            WHERE v.UserId = u.Id
              AND v.VoteTypeId = 2
        ) AS ReceivedUpvotes,
        (
            SELECT COUNT(DISTINCT v.PostId)
            FROM Votes v
            WHERE v.UserId = u.Id
              AND v.VoteTypeId = 3
        ) AS ReceivedDownvotes
    FROM Users u
    JOIN RankedUserPosts rup ON u.Id = rup.OwnerUserId
    WHERE rup.rn = 1
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
HighReputationUsers AS (
    SELECT UserId
    FROM UserPostStats
    WHERE Reputation > 10000
),
RecentQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.Title,
        p.AnswerCount,
        p.FavoriteCount,
        p.Score,
        p.ViewCount,
        p.ClosedDate,
        p.CommunityOwnedDate,
        u.DisplayName AS OwnerDisplayName,
        (
            SELECT COUNT(*)
            FROM Comments c
            WHERE c.PostId = p.Id
              AND c.Score > 5
        ) AS HighScoringCommentsCount,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            WHEN EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - p.CreationDate)) / 86400.0 < 7 THEN 'Recent'
            ELSE 'Established'
        END AS PostStatusCategory,
        p.CreationDate
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '90 day')
),
QuestionMetrics AS (
    SELECT
        rq.QuestionId,
        rq.Title,
        rq.OwnerDisplayName,
        rq.AnswerCount,
        rq.FavoriteCount,
        rq.Score,
        rq.ViewCount,
        rq.PostStatusCategory,
        rq.HighScoringCommentsCount,
        (
            SELECT COUNT(*)
            FROM PostLinks pl
            WHERE pl.PostId = rq.QuestionId
              AND pl.LinkTypeId = 3
        ) AS DuplicateLinkCount,
        ROW_NUMBER() OVER(ORDER BY rq.Score DESC, rq.FavoriteCount DESC) AS ScoreRank,
        RANK() OVER(PARTITION BY rq.PostStatusCategory ORDER BY rq.ViewCount DESC) AS ViewRankInCategory,
        rq.CreationDate,
        rq.ClosedDate
    FROM RecentQuestions rq
),
UserContributionSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS AvgAnswerScore,
        MAX(u.Views) AS UserViews,
        (
            SELECT COUNT(*)
            FROM Badges b
            WHERE b.UserId = u.Id
              AND b.Class = 1
        ) AS GoldBadges,
        (
            SELECT COUNT(*)
            FROM Badges b
            WHERE b.UserId = u.Id
              AND b.Class = 2
        ) AS SilverBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
)
SELECT
    qm.Title AS QuestionTitle,
    qm.OwnerDisplayName,
    qm.Score,
    qm.ViewRankInCategory,
    qm.ScoreRank,
    qm.PostStatusCategory,
    ups.TotalQuestions AS UserTotalQuestions,
    ups.TotalQuestionScore AS UserTotalQuestionScore,
    ups.ReceivedUpvotes AS UserReceivedUpvotes,
    ups.ReceivedDownvotes AS UserReceivedDownvotes,
    uc.QuestionCount AS UserSpecificQuestionCount,
    uc.AnswerCount AS UserSpecificAnswerCount,
    uc.AvgAnswerScore AS UserAvgAnswerScore,
    uc.GoldBadges,
    uc.SilverBadges,
    CASE
        WHEN qm.Score > 100 AND qm.FavoriteCount > 50 THEN 'Highly Popular'
        WHEN qm.DuplicateLinkCount > 0 THEN 'Has Duplicate Links'
        WHEN qm.HighScoringCommentsCount > 3 THEN 'Active Discussion'
        ELSE 'Standard'
    END AS QuestionEngagementLevel,
    LOWER(CONCAT(qm.OwnerDisplayName, '-', CAST(qm.QuestionId AS TEXT))) AS DerivedIdentifier,
    CASE
        WHEN ups.Reputation > uc.Reputation THEN 'Senior User'
        WHEN ups.Reputation < uc.Reputation THEN 'Emerging User'
        ELSE 'Peer User'
    END AS ReputationComparison,
    COALESCE(qm.ClosedDate, qm.CreationDate) AS EffectiveDate,
    qm.ViewCount AS qm_ViewCount,
    qm.AnswerCount AS qm_AnswerCount,
    ups.EditCount AS ups_EditCount,
    ups.Reputation AS ups_Reputation,
    uc.Reputation AS uc_Reputation
FROM QuestionMetrics qm
JOIN UserPostStats ups
  ON qm.OwnerDisplayName = ups.DisplayName
JOIN UserContributionSummary uc
  ON qm.OwnerDisplayName = uc.DisplayName
WHERE ups.Reputation > 1000
  AND qm.ViewCount > 500
  AND qm.AnswerCount BETWEEN 5 AND 50
  AND qm.DuplicateLinkCount <= 2
  AND ups.EditCount >= 0
ORDER BY qm.Score DESC, qm.ViewCount DESC
LIMIT 100;