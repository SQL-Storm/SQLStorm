WITH UserPostScores AS (
    SELECT
        p.OwnerUserId,
        SUM(p.Score) AS TotalScore,
        COUNT(p.Id) AS PostCount,
        AVG(CAST(p.ViewCount AS NUMERIC)) AS AvgViewCount,
        MAX(p.CreationDate) AS LastPostDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.PostTypeId IN (1, 2)
    GROUP BY p.OwnerUserId
),
TopUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        ups.TotalScore,
        ups.PostCount,
        ups.AvgViewCount,
        ups.LastPostDate,
        LAG(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation DESC) AS PrevReputation,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    JOIN UserPostScores ups ON u.Id = ups.OwnerUserId
    WHERE u.Reputation > 1000
),
UserComments AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS CommentCount,
        AVG(CAST(c.Score AS NUMERIC)) AS AvgCommentScore,
        SUM(CASE WHEN c.Text LIKE '%interesting%' THEN 1 ELSE 0 END) AS InterestingCommentCount,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
PostHistoryEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        COUNT(ph.Id) AS EditCount,
        MIN(ph.CreationDate) AS FirstEditDate,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY ph.PostId, ph.UserId
),
-- Compute last edit row_number per user-post so we can count last-edited posts per user without nesting window inside aggregate
PostHistoryEditsWithRowNum AS (
    SELECT
        phe.PostId,
        phe.UserId,
        phe.EditCount,
        phe.FirstEditDate,
        phe.LastEditDate,
        ROW_NUMBER() OVER (PARTITION BY phe.UserId ORDER BY phe.LastEditDate DESC) AS rn_per_user
    FROM PostHistoryEdits phe
),
PostEditAnalysis AS (
    SELECT
        phe.UserId,
        COUNT(DISTINCT phe.PostId) AS EditedPostCount,
        SUM(phe.EditCount) AS TotalEdits,
        AVG(CAST(phe.EditCount AS NUMERIC)) AS AvgEditsPerPost,
        SUM(CASE WHEN phe_with_rn.rn_per_user = 1 THEN 1 ELSE 0 END) AS LastEditedPostCount
    FROM PostHistoryEdits phe
    LEFT JOIN PostHistoryEditsWithRowNum phe_with_rn
        ON phe.PostId = phe_with_rn.PostId
        AND phe.UserId = phe_with_rn.UserId
        AND phe.EditCount = phe_with_rn.EditCount
        AND phe.LastEditDate = phe_with_rn.LastEditDate
    GROUP BY phe.UserId
)
SELECT
    tu.Id AS UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.TotalScore,
    tu.PostCount,
    tu.AvgViewCount,
    tu.LastPostDate,
    COALESCE(uc.CommentCount, 0) AS UserCommentCount,
    COALESCE(uc.AvgCommentScore, 0) AS UserAvgCommentScore,
    COALESCE(uc.InterestingCommentCount, 0) AS UserInterestingCommentCount,
    COALESCE(uca.EditedPostCount, 0) AS UserEditedPostCount,
    COALESCE(uca.TotalEdits, 0) AS UserTotalEdits,
    CASE
        WHEN tu.PrevReputation IS NULL OR tu.PrevReputation = 0 THEN 'TopRank'
        WHEN tu.Reputation > tu.PrevReputation * 1.5 THEN 'SignificantGrowth'
        WHEN tu.Reputation < tu.PrevReputation * 0.7 THEN 'ReputationDrop'
        ELSE 'Stable'
    END AS ReputationTrend,
    CASE
        WHEN tu.LastPostDate > cast('2024-10-01' as date) - INTERVAL '30 day' THEN 'ActiveRecent'
        WHEN tu.LastPostDate > cast('2024-10-01' as date) - INTERVAL '365 day' THEN 'ActivePastYear'
        ELSE 'InactiveLongAgo'
    END AS UserActivityStatus,
    (
        SELECT COUNT(*)
        FROM Badges b
        WHERE b.UserId = tu.Id AND b.Class = 1
    ) AS GoldBadgeCount,
    (
        SELECT COUNT(*)
        FROM Badges b
        WHERE b.UserId = tu.Id AND b.Class = 2
    ) AS SilverBadgeCount,
    (
        SELECT COUNT(*)
        FROM Badges b
        WHERE b.UserId = tu.Id AND b.Class = 3
    ) AS BronzeBadgeCount,
    (
        SELECT COUNT(DISTINCT pl.RelatedPostId)
        FROM PostLinks pl
        JOIN Posts p ON pl.PostId = p.Id
        WHERE p.OwnerUserId = tu.Id AND pl.LinkTypeId = 3
    ) AS DuplicateLinksCreated,
    (
        SELECT SUM(CASE WHEN COALESCE(p.ClosedDate, p.CommunityOwnedDate) IS NOT NULL THEN 1 ELSE 0 END)
        FROM Posts p
        WHERE p.OwnerUserId = tu.Id AND p.PostTypeId = 1
    ) AS ClosedOrCommunityOwnedQuestions
FROM TopUsers tu
LEFT JOIN UserComments uc ON tu.Id = uc.UserId
LEFT JOIN PostEditAnalysis uca ON tu.Id = uca.UserId
ORDER BY tu.ReputationRank
LIMIT 100;