-- {"query": "18015.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1234} 

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
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
    GROUP BY ph.PostId, ph.UserId
),
PostEditAnalysis AS (
    SELECT
        phe.UserId,
        COUNT(DISTINCT phe.PostId) AS EditedPostCount,
        SUM(phe.EditCount) AS TotalEdits,
        AVG(CAST(phe.EditCount AS NUMERIC)) AS AvgEditsPerPost,
        COUNT(CASE WHEN ROW_NUMBER() OVER(PARTITION BY phe.UserId ORDER BY phe.LastEditDate DESC) = 1 THEN 1 ELSE NULL END) AS LastEditedPostCount -- Count of users who made their last edit on a specific post
    FROM PostHistoryEdits phe
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
        WHEN tu.LastPostDate > DATE('now', '-30 day') THEN 'ActiveRecent'
        WHEN tu.LastPostDate > DATE('now', '-365 day') THEN 'ActivePastYear'
        ELSE 'InactiveLongAgo'
    END AS UserActivityStatus,
    (
        SELECT COUNT(*)
        FROM Badges b
        WHERE b.UserId = tu.Id AND b.Class = 1 -- Gold Badges
    ) AS GoldBadgeCount,
    (
        SELECT COUNT(*)
        FROM Badges b
        WHERE b.UserId = tu.Id AND b.Class = 2 -- Silver Badges
    ) AS SilverBadgeCount,
    (
        SELECT COUNT(*)
        FROM Badges b
        WHERE b.UserId = tu.Id AND b.Class = 3 -- Bronze Badges
    ) AS BronzeBadgeCount,
    (
        SELECT COUNT(DISTINCT pl.RelatedPostId)
        FROM PostLinks pl
        JOIN Posts p ON pl.PostId = p.Id
        WHERE p.OwnerUserId = tu.Id AND pl.LinkTypeId = 3 -- Duplicate Link
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
