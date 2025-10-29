-- {"query": "4784.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1449} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.AnswerCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostNumberForUser,
        SUM(p.Score) OVER (PARTITION BY p.OwnerUserId) AS TotalScoreByUser,
        AVG(CAST(p.AnswerCount AS DECIMAL)) OVER (PARTITION BY p.OwnerUserId) AS AvgAnswersByUser,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 1
            ELSE 0
        END AS IsClosedFlag
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 -- Questions only
),
PostHistoryAnalysis AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 END) AS TitleEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 END) AS BodyEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) THEN 1 END) AS CloseVotes,
        MAX(CASE WHEN ph.PostHistoryTypeId = 19 THEN ph.CreationDate ELSE NULL END) AS LastProtectionDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 10, 19) AND ph.PostId IN (SELECT Id FROM Posts WHERE PostTypeId = 1)
    GROUP BY ph.PostId
),
UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT p.Id) AS PostCount
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
DetailedPostInfo AS (
    SELECT
        rp.PostId,
        rp.Title,
        rp.OwnerUserId,
        rp.OwnerDisplayName,
        rp.PostCreationDate,
        rp.Score,
        rp.AnswerCount,
        rp.FavoriteCount,
        rp.TotalScoreByUser,
        rp.AvgAnswersByUser,
        rp.IsClosedFlag,
        pha.TitleEdits,
        pha.BodyEdits,
        pha.CloseVotes,
        pha.LastProtectionDate,
        CASE
            WHEN rp.FavoriteCount > 0 AND rp.AnswerCount > 0 THEN (rp.FavoriteCount * 1.0 / rp.AnswerCount)
            WHEN rp.FavoriteCount > 0 THEN rp.FavoriteCount
            ELSE 0
        END AS FavoriteToAnswerRatio,
        DATEDIFF(day, rp.PostCreationDate, GETDATE()) AS DaysSinceCreation,
        rp.PostNumberForUser,
        UPPER(LEFT(rp.Title, 1)) AS FirstLetterOfTitle,
        REPLACE(rp.Title, ' ', '_') AS TitleWithUnderscores
    FROM RankedPosts rp
    LEFT JOIN PostHistoryAnalysis pha ON rp.PostId = pha.PostId
    WHERE rp.Score > 10 AND rp.AnswerCount > 0
)
SELECT
    dpi.PostId,
    dpi.Title,
    dpi.OwnerUserId,
    dpi.OwnerDisplayName,
    dpi.PostCreationDate,
    dpi.Score,
    dpi.AnswerCount,
    dpi.FavoriteCount,
    dpi.TotalScoreByUser,
    dpi.AvgAnswersByUser,
    dpi.IsClosedFlag,
    dpi.TitleEdits,
    dpi.BodyEdits,
    dpi.CloseVotes,
    CASE
        WHEN dpi.LastProtectionDate IS NOT NULL THEN 'Protected'
        ELSE 'Not Protected'
    END AS ProtectionStatus,
    dpi.FavoriteToAnswerRatio,
    dpi.DaysSinceCreation,
    dpi.PostNumberForUser,
    CONCAT(dpi.FirstLetterOfTitle, '-', dpi.TitleWithUnderscores) AS FormattedTitle,
    uas.UserName AS TopContributorName,
    uas.Reputation AS TopContributorReputation,
    uas.BadgeCount AS TopContributorBadgeCount,
    COALESCE(uas.UpVotesReceived, 0) AS TopContributorUpVotes,
    COALESCE(uas.DownVotesReceived, 0) AS TopContributorDownVotes,
    COALESCE(uas.CommentCount, 0) AS TopContributorComments,
    COALESCE(uas.PostCount, 0) AS TopContributorPosts,
    CASE
        WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = dpi.PostId AND pl.LinkTypeId = 3) THEN 'Is Duplicate'
        ELSE 'Not a Duplicate'
    END AS DuplicateStatus,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = dpi.PostId AND c.Score > 5) AS HighScoringComments
FROM DetailedPostInfo dpi
JOIN UserActivitySummary uas ON dpi.OwnerUserId = uas.UserId
WHERE dpi.DaysSinceCreation > 30
  AND dpi.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1)
  AND dpi.FavoriteToAnswerRatio BETWEEN 0.1 AND 2.0
  AND uas.Reputation > 10000
ORDER BY dpi.Score DESC, dpi.FavoriteCount DESC
LIMIT 100;
