WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.CommunityOwnedDate,
        ROW_NUMBER() OVER(PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank,
        COUNT(c.Id) OVER(PARTITION BY p.Id) AS CommentCountForPost,
        AVG(CAST(p.Score AS DECIMAL(10,2))) OVER(PARTITION BY p.PostTypeId) AS AvgScoreForPostType,
        LAG(p.Score, 1, 0) OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS PreviousScore,
        LEAD(p.Score, 1, 0) OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS NextScore,
        SUM(p.ViewCount) OVER(PARTITION BY p.PostTypeId ORDER BY p.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeViewCountForType,
        CASE
            WHEN p.ClosedDate IS NOT NULL AND p.ClosedDate < (cast('2024-10-01' as date) - INTERVAL '365 days') THEN 'Closed_Over_1_Year_Ago'
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed_Recently'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community_Owned'
            WHEN p.Score > 1000 THEN 'High_Score'
            WHEN p.FavoriteCount > 50 THEN 'Highly_Favorited'
            ELSE 'Regular'
        END AS PostCategorization
    FROM Posts AS p
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users AS u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments AS c ON p.Id = c.PostId
    WHERE p.PostTypeId IN (1, 2) AND p.CreationDate BETWEEN (cast('2024-10-01' as date) - INTERVAL '730 days') AND cast('2024-10-01' as date)
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalScore,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users AS u
    JOIN Posts AS p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate > (cast('2024-10-01' as date) - INTERVAL '1095 days')
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(p.Id) > 10
),
TopQuestions AS (
    SELECT
        PostId,
        OwnerUserId,
        Score,
        PostCreationDate,
        ROW_NUMBER() OVER (ORDER BY Score DESC, PostCreationDate ASC) AS RankWithinAllQuestions
    FROM RankedPosts
    WHERE PostTypeId = 1 AND Score > 0
),
PotentialDuplicateLinks AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkType
    FROM PostLinks AS pl
    JOIN LinkTypes AS lt ON pl.LinkTypeId = lt.Id
    WHERE lt.Name = 'Duplicate'
),
PostHistorySummary AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 1 THEN ph.Id END) AS InitialTitleEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 2 THEN ph.Id END) AS InitialBodyEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 3 THEN ph.Id END) AS InitialTagEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 4 THEN ph.Id END) AS TitleEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 5 THEN ph.Id END) AS BodyEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 6 THEN ph.Id END) AS TagEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) THEN ph.Id END) AS CloseVotes,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 13 THEN ph.Id END) AS UndeleteEvents
    FROM PostHistory AS ph
    GROUP BY ph.PostId
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.OwnerUserId,
    rp.OwnerDisplayName,
    rp.PostCreationDate,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.ClosedDate,
    rp.CommunityOwnedDate,
    rp.ScoreRank,
    rp.CommentCountForPost,
    rp.AvgScoreForPostType,
    rp.PreviousScore,
    rp.NextScore,
    rp.CumulativeViewCountForType,
    rp.PostCategorization,
    ua.TotalPosts AS UserTotalPosts,
    ua.TotalScore AS UserTotalScore,
    ua.QuestionCount AS UserQuestionCount,
    ua.AnswerCount AS UserAnswerCount,
    ua.AvgPostScore AS UserAvgPostScore,
    ua.LastPostDate AS UserLastPostDate,
    tq.RankWithinAllQuestions,
    COALESCE(pd.LinkType, 'No Duplicate Link') AS DuplicateLinkStatus,
    COALESCE(phs.TitleEdits, 0) AS TotalTitleEdits,
    COALESCE(phs.BodyEdits, 0) AS TotalBodyEdits,
    COALESCE(phs.TagEdits, 0) AS TotalTagEdits,
    COALESCE(phs.CloseVotes, 0) AS TotalCloseVotes,
    COALESCE(phs.UndeleteEvents, 0) AS TotalUndeleteEvents,
    CASE
        WHEN rp.OwnerUserId IS NULL THEN 'Anonymous'
        WHEN rp.OwnerUserId = -1 THEN 'Community User'
        WHEN rp.OwnerDisplayName LIKE '%test%' THEN 'Test User'
        WHEN SUBSTRING(COALESCE(u.Location, ''), 1, 5) = 'Earth' THEN 'Earth Resident'
        ELSE UPPER(SUBSTRING(rp.PostTypeName, 1, 1) || SUBSTRING(rp.PostTypeName, LENGTH(rp.PostTypeName) - 1))
    END AS DerivedUserInfo,
    CASE
        WHEN rp.Score > (rp.NextScore + rp.PreviousScore) / 2 THEN 'Score Above Average Trend'
        WHEN rp.Score < (rp.NextScore + rp.PreviousScore) / 2 THEN 'Score Below Average Trend'
        ELSE 'Score Matches Average Trend'
    END AS ScoreTrendComparison,
    CASE
        WHEN rp.PostTypeName = 'Question' AND rp.AnswerCount > 10 AND rp.Score > 100 THEN 'Popular Question'
        WHEN rp.PostTypeName = 'Answer' AND rp.Score > 50 AND rp.CommentCountForPost > 5 THEN 'Engaged Answer'
        ELSE 'Standard Post'
    END AS PostEngagementLevel,
    CONCAT(rp.PostTypeName, ' - ', COALESCE(rp.OwnerDisplayName, 'Unknown')) AS PostIdentifier,
    CAST(rp.PostCreationDate AS DATE) AS PostDateOnly,
    rp.Score * rp.ViewCount AS ScoreViewProduct,
    rp.Score + rp.AnswerCount + rp.CommentCount AS TotalEngagementMetrics,
    CASE WHEN rp.ClosedDate IS NULL THEN 0 ELSE 1 END AS IsClosedInt,
    CASE WHEN rp.CommunityOwnedDate IS NOT NULL THEN TRUE ELSE FALSE END AS IsCommunityOwnedBool,
    COALESCE(rp.FavoriteCount, 0) AS SafeFavoriteCount,
    rp.Score + COALESCE(rp.FavoriteCount, 0) AS AdjustedScore,
    rp.Score - COALESCE(rp.FavoriteCount, 0) AS ScoreMinusFavorites
FROM RankedPosts AS rp
LEFT JOIN UserActivity AS ua ON rp.OwnerUserId = ua.UserId
LEFT JOIN TopQuestions AS tq ON rp.PostId = tq.PostId
LEFT JOIN PotentialDuplicateLinks AS pd ON rp.PostId = pd.PostId
LEFT JOIN PostHistorySummary AS phs ON rp.PostId = phs.PostId
LEFT JOIN Users AS u ON rp.OwnerUserId = u.Id
WHERE rp.ScoreRank <= 100 OR rp.PostCategorization = 'High_Score' OR rp.AvgScoreForPostType > 10
ORDER BY rp.PostCreationDate DESC
LIMIT 500;