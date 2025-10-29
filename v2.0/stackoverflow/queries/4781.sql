WITH CTE_UserPostActivity AS (
    SELECT
        p.OwnerUserId,
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        pt.Name AS PostTypeName,
        CASE
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PrimaryPostType,
        CASE
            WHEN p.PostTypeId = 1 THEN
                (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.CreationDate BETWEEN p.CreationDate AND (p.CreationDate + INTERVAL '7' DAY))
            ELSE 0
        END AS FirstWeekCommentCount,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostRank
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL
),
CTE_UserVoteStats AS (
    SELECT
        v.UserId,
        COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS TotalUpVotesReceived,
        COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS TotalDownVotesReceived,
        SUM(CASE WHEN vt.Name = 'AcceptedByOriginator' THEN 1 ELSE 0 END) AS AcceptedAnswers,
        COUNT(CASE WHEN vt.Name = 'Favorite' THEN 1 END) AS Favorites
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY v.UserId
),
CTE_UserPostHistory AS (
    SELECT
        ph.UserId,
        COUNT(CASE WHEN pht.Name IN ('Edit Title', 'Edit Body', 'Edit Tags') THEN 1 END) AS EditsMade,
        COUNT(CASE WHEN pht.Name IN ('Post Closed', 'Post Reopened', 'Post Deleted', 'Post Undeleted') THEN 1 END) AS ModerationActions,
        MAX(ph.CreationDate) AS LastActivityDate
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    GROUP BY ph.UserId
),
CTE_UserBadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        STRING_AGG(b.Name, '; ') AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId
),
CTE_ComplexCalculations AS (
    SELECT
        upa.OwnerUserId,
        upa.Id AS PostId,
        upa.PostTypeId,
        pt.Name AS PostTypeName,
        CASE
            WHEN upa.PostTypeId = 1 THEN 'Question'
            WHEN upa.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PrimaryPostType,
        upa.Score AS PostScore,
        upa.ViewCount AS PostViewCount,
        CASE
            WHEN upa.ViewCount > 1000 AND upa.Score > 10 THEN CAST(upa.Score * 1.5 + upa.ViewCount * 0.1 AS NUMERIC(10, 2))
            WHEN upa.Score > 5 THEN CAST(upa.Score * 1.2 AS NUMERIC(10, 2))
            ELSE CAST(upa.Score AS NUMERIC(10, 2))
        END AS WeightedScore,
        CONCAT(
            'Tags: ',
            COALESCE(REPLACE(REPLACE(upa.Tags, '<', ' '), '>', ' '), 'N/A'),
            ' | Community Owned: ',
            CASE WHEN upa.CommunityOwnedDate IS NOT NULL THEN 'Yes' ELSE 'No' END
        ) AS PostDetails,
        CASE
            WHEN LAG(upa.CreationDate, 1, upa.CreationDate) OVER (PARTITION BY upa.OwnerUserId ORDER BY upa.CreationDate) < (upa.CreationDate - INTERVAL '30' DAY) THEN 'Significant Gap'
            ELSE 'Normal Cadence'
        END AS PostCadence,
        CASE
            WHEN (SELECT COUNT(*) FROM Comments c WHERE c.PostId = upa.Id AND c.CreationDate BETWEEN upa.CreationDate AND (upa.CreationDate + INTERVAL '7' DAY)) > 5 THEN 'High Initial Engagement'
            WHEN (SELECT COUNT(*) FROM Comments c WHERE c.PostId = upa.Id AND c.CreationDate BETWEEN upa.CreationDate AND (upa.CreationDate + INTERVAL '7' DAY)) > 0 THEN 'Some Initial Engagement'
            ELSE 'Low Initial Engagement'
        END AS InitialEngagementLevel,
        upa.CreationDate AS PostCreationDate,
        upa.Tags,
        upa.CommunityOwnedDate
    FROM Posts upa
    JOIN PostTypes pt ON upa.PostTypeId = pt.Id
    WHERE upa.OwnerUserId IS NOT NULL AND upa.PostTypeId IN (1, 2)
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    COALESCE(uvs.TotalUpVotesReceived, 0) AS TotalUpVotesReceived,
    COALESCE(uvs.TotalDownVotesReceived, 0) AS TotalDownVotesReceived,
    COALESCE(uvs.AcceptedAnswers, 0) AS AcceptedAnswers,
    COALESCE(uvs.Favorites, 0) AS Favorites,
    COALESCE(upst.EditsMade, 0) AS EditsMade,
    COALESCE(upst.ModerationActions, 0) AS ModerationActions,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
    cc.PostId,
    cc.PostTypeName,
    cc.PrimaryPostType,
    cc.PostScore,
    cc.PostViewCount,
    cc.WeightedScore,
    cc.PostDetails,
    cc.PostCadence,
    cc.InitialEngagementLevel,
    CASE
        WHEN u.Views > 1000000 AND u.UpVotes > 50000 THEN 'Elite User'
        WHEN u.Reputation > 10000 AND COALESCE(ubs.GoldBadges, 0) >= 5 THEN 'Badge Master'
        ELSE 'Regular User'
    END AS UserTier,
    CASE
        WHEN cc.PostScore < 0 THEN 'Negative Score'
        WHEN cc.PostScore BETWEEN 0 AND 10 THEN 'Low Score'
        WHEN cc.PostScore > 10 THEN 'High Score'
        ELSE 'No Score'
    END AS ScoreCategory,
    CASE
        WHEN cc.PostCreationDate < (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '365' DAY) AND cc.InitialEngagementLevel = 'Low Initial Engagement' THEN 'Struggled Early'
        WHEN cc.PostCreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY) AND cc.InitialEngagementLevel <> 'Low Initial Engagement' THEN 'Recent Active'
        ELSE 'Standard Activity'
    END AS ActivityPattern,
    SUBSTRING(u.AboutMe FROM 1 FOR 100) AS AboutMeExcerpt,
    CASE WHEN u.WebsiteUrl IS NULL OR u.WebsiteUrl = '' THEN 'No Website' ELSE 'Has Website' END AS WebsiteStatus,
    SPLIT_PART(u.DisplayName, ' ', 1) AS FirstName,
    CASE
        WHEN u.DisplayName LIKE '% %' THEN 'Has Spaces'
        ELSE 'No Spaces'
    END AS DisplayNameFormat,
    COALESCE(ubs.BadgeNames, 'No Badges') AS BadgeSummary,
    CASE
        WHEN cc.PostScore IS NULL THEN 'Score is NULL'
        WHEN cc.PostScore = 0 THEN 'Score is Zero'
        ELSE 'Score is Non-Zero'
    END AS ScorePresence,
    CASE WHEN NULLIF(COALESCE(cc.PostScore, 0), 0) IS NULL THEN NULL ELSE CAST(COALESCE(cc.PostViewCount, 0) AS DOUBLE PRECISION) / NULLIF(COALESCE(cc.PostScore, 0), 0) END AS ViewsPerScoreRatio,
    EXISTS (SELECT 1 FROM Badges WHERE UserId = u.Id AND Name LIKE '%Great Answer%') AS HasGreatAnswerBadge,
    CASE
        WHEN cc.PostCadence = 'Significant Gap' AND cc.PostScore > 5 THEN 'Potential Hibernation Break'
        ELSE NULL
    END AS SpecialStatus
FROM Users u
LEFT JOIN CTE_UserVoteStats uvs ON u.Id = uvs.UserId
LEFT JOIN CTE_UserPostHistory upst ON u.Id = upst.UserId
LEFT JOIN CTE_UserBadgeSummary ubs ON u.Id = ubs.UserId
LEFT JOIN CTE_ComplexCalculations cc ON u.Id = cc.OwnerUserId
WHERE u.Reputation > 100
  AND u.CreationDate < (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '180' DAY)
  AND cc.PostId IS NOT NULL
  AND cc.PostTypeName NOT LIKE '%TagWiki%'
  AND cc.PostTypeName NOT LIKE '%PrivilegeWiki%'
  AND (cc.PostScore > 0 OR cc.PostViewCount > 500)
GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.AboutMe,
    u.WebsiteUrl,
    cc.PostId,
    cc.PostTypeName,
    cc.PrimaryPostType,
    cc.PostScore,
    cc.PostViewCount,
    cc.WeightedScore,
    cc.PostDetails,
    cc.PostCadence,
    cc.InitialEngagementLevel,
    cc.PostCreationDate,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.BadgeNames,
    uvs.TotalUpVotesReceived,
    uvs.TotalDownVotesReceived,
    uvs.AcceptedAnswers,
    uvs.Favorites,
    upst.EditsMade,
    upst.ModerationActions
ORDER BY u.Reputation DESC, u.CreationDate ASC
LIMIT 1000;