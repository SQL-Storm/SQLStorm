WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL
),
UserPostCounts AS (
    SELECT
        OwnerUserId,
        COUNT(Id) AS TotalPostsOwned,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
),
UserBadges AS (
    SELECT
        ub.UserId,
        COUNT(CASE WHEN ub.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN ub.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN ub.Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(CASE WHEN ub.Name = 'Tagger' THEN ub.Date ELSE NULL END) AS TaggerBadgeDate
    FROM Badges ub
    GROUP BY ub.UserId
),
UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COALESCE(upc.TotalPostsOwned, 0) AS TotalPostsOwned,
        COALESCE(upc.QuestionCount, 0) AS QuestionsAsked,
        COALESCE(upc.AnswerCount, 0) AS AnswersGiven,
        COALESCE(ub.GoldBadges, 0) AS GoldBadges,
        COALESCE(ub.SilverBadges, 0) AS SilverBadges,
        COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
        CASE WHEN ub.TaggerBadgeDate IS NOT NULL THEN 1 ELSE 0 END AS HasTaggerBadge
    FROM Users u
    LEFT JOIN UserPostCounts upc ON u.Id = upc.OwnerUserId
    LEFT JOIN UserBadges ub ON u.Id = ub.UserId
    WHERE u.Views > 1000 AND u.Reputation > 5000
),
HighScoringQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.CreationDate
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Score > 100
      AND EXTRACT(YEAR FROM p.CreationDate) BETWEEN EXTRACT(YEAR FROM (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '5' YEAR)) AND EXTRACT(YEAR FROM TIMESTAMP '2024-10-01 12:34:56')
),
FrequentCommenters AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS CommentCount
    FROM Comments c
    JOIN Posts p ON c.PostId = p.Id
    WHERE c.UserId IS NOT NULL AND p.OwnerUserId <> c.UserId
    GROUP BY c.UserId
    HAVING COUNT(c.Id) > 50
),
PostsWithHighCommentActivity AS (
    SELECT
        ph.PostId,
        COUNT(ph.Id) AS PostHistoryEntries
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE pht.Name IN ('Edit Body', 'Edit Title', 'Post Closed', 'Post Reopened', 'Post Deleted', 'Post Undeleted')
    GROUP BY ph.PostId
    HAVING COUNT(ph.Id) > 20
)
SELECT
    uas.DisplayName AS UserName,
    uas.Reputation,
    uas.QuestionsAsked,
    uas.AnswersGiven,
    uas.GoldBadges,
    uas.SilverBadges,
    uas.BronzeBadges,
    uas.HasTaggerBadge,
    COALESCE(hsq.Title, 'N/A') AS TopQuestionTitle,
    COALESCE(hsq.Score, 0) AS TopQuestionScore,
    COALESCE(fch.CommentCount, 0) AS FrequentCommenterActivity,
    COALESCE(pwhca.PostHistoryEntries, 0) AS HighPostHistoryActivity,
    CASE
        WHEN uas.UserCreationDate < (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2' YEAR) AND uas.TotalPostsOwned > 1000 THEN 'Veteran Contributor'
        WHEN uas.Reputation > 100000 AND uas.GoldBadges > 10 THEN 'Highly Esteemed'
        WHEN uas.AnswersGiven > uas.QuestionsAsked * 2 THEN 'Answer Focused'
        ELSE 'General Contributor'
    END AS UserCategory,
    SUBSTRING(uas.DisplayName FROM 1 FOR 3) AS NamePrefix,
    CASE WHEN uas.Reputation > 50000 THEN 'High' ELSE 'Medium' END AS ReputationTier,
    LPAD(CAST(uas.QuestionsAsked AS VARCHAR), 5, '0') AS FormattedQuestionCount,
    COALESCE(CAST(uas.AnswersGiven AS VARCHAR) || '-' || CAST(uas.QuestionsAsked AS VARCHAR), 'N/A') AS AnswerQuestionRatio,
    CASE
        WHEN uas.UserCreationDate IS NULL THEN 'Unknown'
        WHEN uas.UserCreationDate < (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6' MONTH) THEN 'Recent'
        ELSE 'Established'
    END AS UserTenure,
    LAG(uas.Reputation, 1, 0) OVER (ORDER BY uas.Reputation DESC) AS PreviousReputation,
    ROW_NUMBER() OVER (ORDER BY uas.Reputation DESC, uas.TotalPostsOwned DESC) AS RankByReputation
FROM UserActivitySummary uas
LEFT JOIN (
    SELECT hq_owner.OwnerUserId, hq_owner.Title, hq_owner.Score, ROW_NUMBER() OVER (PARTITION BY hq_owner.OwnerUserId ORDER BY hq_owner.Score DESC, hq_owner.CreationDate DESC) AS rn
    FROM HighScoringQuestions hq_owner
) hsq ON uas.UserId = hsq.OwnerUserId AND hsq.rn = 1
LEFT JOIN FrequentCommenters fch ON uas.UserId = fch.UserId
LEFT JOIN PostsWithHighCommentActivity pwhca ON uas.UserId = (
    SELECT p2.OwnerUserId FROM Posts p2 WHERE p2.Id = pwhca.PostId LIMIT 1
)
GROUP BY
    uas.DisplayName,
    uas.Reputation,
    uas.QuestionsAsked,
    uas.AnswersGiven,
    uas.GoldBadges,
    uas.SilverBadges,
    uas.BronzeBadges,
    uas.HasTaggerBadge,
    hsq.Title,
    hsq.Score,
    fch.CommentCount,
    pwhca.PostHistoryEntries,
    uas.UserCreationDate,
    uas.TotalPostsOwned,
    uas.UserId
ORDER BY uas.Reputation DESC, uas.TotalPostsOwned DESC
LIMIT 100;