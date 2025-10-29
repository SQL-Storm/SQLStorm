WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate AS EditDate,
        ph.PostHistoryTypeId,
        pht.Name AS EditType,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
UserPostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS TotalPostsOwned,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsOwned,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersOwned,
        AVG(p.Score) AS AveragePostScore,
        MAX(p.CreationDate) AS LatestPostDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY p.OwnerUserId
),
RecentEditCounts AS (
    SELECT
        UserId,
        COUNT(*) AS RecentEditsCount,
        MAX(EditDate) AS LatestEditDate
    FROM RankedPostEdits
    WHERE rn = 1
      AND EditDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90' DAY)
    GROUP BY UserId
),
HighReputationUsers AS (
    SELECT
        Id AS UserId,
        DisplayName,
        Reputation,
        CreationDate AS UserCreationDate,
        Views AS UserViews,
        UpVotes AS UserUpVotes,
        DownVotes AS UserDownVotes
    FROM Users
    WHERE Reputation > 10000
),
CombinedUserData AS (
    SELECT
        hru.UserId,
        hru.DisplayName,
        hru.Reputation,
        hru.UserCreationDate,
        hru.UserViews,
        hru.UserUpVotes,
        hru.UserDownVotes,
        COALESCE(upa.TotalPostsOwned, 0) AS TotalPostsOwned,
        COALESCE(upa.QuestionsOwned, 0) AS QuestionsOwned,
        COALESCE(upa.AnswersOwned, 0) AS AnswersOwned,
        COALESCE(upa.AveragePostScore, 0.0) AS AveragePostScore,
        COALESCE(rec.RecentEditsCount, 0) AS RecentEditsCount,
        CASE WHEN rec.UserId IS NULL THEN 'No Recent Edits' ELSE 'Made Recent Edits' END AS EditStatus
    FROM HighReputationUsers hru
    LEFT JOIN UserPostActivity upa ON hru.UserId = upa.OwnerUserId
    LEFT JOIN RecentEditCounts rec ON hru.UserId = rec.UserId
)
SELECT
    cdu.DisplayName,
    cdu.Reputation,
    cdu.UserCreationDate,
    cdu.UserViews,
    cdu.TotalPostsOwned,
    cdu.QuestionsOwned,
    cdu.AnswersOwned,
    ROUND(cdu.AveragePostScore, 2) AS AvgScore,
    cdu.RecentEditsCount,
    cdu.EditStatus,
    CASE
        WHEN cdu.Reputation > 50000 THEN 'High'
        WHEN cdu.Reputation BETWEEN 10001 AND 50000 THEN 'Medium'
        ELSE 'Low'
    END AS ReputationTier,
    COALESCE(CAST(cdu.UserUpVotes AS VARCHAR), 'N/A') AS FormattedUpVotes,
    UPPER(SUBSTRING(cdu.DisplayName FROM 1 FOR 3)) AS DisplayNamePrefix,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM Badges b
            WHERE b.UserId = cdu.UserId AND b.Name LIKE '%Expert%' AND b.Class = 1
        ) THEN 'Gold Expert Badge Holder'
        ELSE 'No Gold Expert Badge'
    END AS ExpertBadgeStatus
FROM CombinedUserData cdu
WHERE cdu.UserCreationDate < (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
GROUP BY
    cdu.DisplayName,
    cdu.Reputation,
    cdu.UserCreationDate,
    cdu.UserViews,
    cdu.TotalPostsOwned,
    cdu.QuestionsOwned,
    cdu.AnswersOwned,
    cdu.AveragePostScore,
    cdu.RecentEditsCount,
    cdu.EditStatus,
    cdu.UserUpVotes,
    cdu.DisplayName,
    cdu.UserId
ORDER BY cdu.Reputation DESC, cdu.UserViews DESC
LIMIT 100;