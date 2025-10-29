-- {"query": "1994.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2254}
WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserDisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPostsByOwner,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsPosted,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersPosted,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        COALESCE(SUM(p.Score), 0) AS TotalPostScoreReceived,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScorePerUser,
        EXTRACT(day FROM (u.LastAccessDate - u.CreationDate)) AS DaysAccountActive,
        u.LastAccessDate AS NextAccessDate,
        (SELECT COUNT(DISTINCT b2.Id) FROM Badges b2 WHERE b2.UserId = u.Id AND b2.Class = 1) AS UserGoldBadgeCount
    FROM
        Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE
        u.Reputation >= 500
        AND u.Views > 10
        AND EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1)
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostContentAnalysis AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.ParentId,
        p.AcceptedAnswerId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.LastActivityDate,
        p.ClosedDate,
        p.Title,
        p.Tags,
        p.Body,
        NULLIF(p.OwnerDisplayName, '') AS EffectiveOwnerDisplayName,
        (SELECT ph.Comment FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10 ORDER BY ph.CreationDate DESC LIMIT 1) AS LatestCloseReasonComment,
        CASE
            WHEN p.Score >= 100 AND p.ViewCount >= 5000 AND p.AnswerCount >= 5 THEN 'Highly Engaged & Solved'
            WHEN p.Score >= 20 AND p.ViewCount >= 500 AND p.CommentCount >= 3 THEN 'Moderately Engaged'
            WHEN p.Body LIKE '%performance%' OR p.Title LIKE '%optimization%' THEN 'Performance Topic'
            ELSE 'General Topic'
        END AS PostEngagementCategory,
        LENGTH(p.Body) AS BodyLength,
        COALESCE(array_length(string_to_array(SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags) - 2)), '><'), 1), 0) AS NumberOfTags,
        ROUND(CAST(p.ViewCount AS DECIMAL) / NULLIF(p.Score, 0), 2) AS ViewsPerScore,
        COALESCE(puc_inner.UpvoteCount, 0) AS UpvoteCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId, DATE_TRUNC('month', p.CreationDate) ORDER BY p.Score DESC, p.ViewCount DESC) AS RankInMonthlyPosts,
        SUBSTRING(p.Body FROM 1 FOR 200) AS BodyExcerpt,
        REPLACE(REPLACE(REPLACE(p.Tags, '<', ''), '>', ','), ',,', ',') AS CleanedTags
    FROM
        Posts p
    LEFT JOIN (
        SELECT v.PostId, COUNT(*) AS UpvoteCount
        FROM Votes v
        WHERE v.VoteTypeId = 2
        GROUP BY v.PostId
    ) puc_inner ON p.Id = puc_inner.PostId
    WHERE
        p.PostTypeId IN (1, 2)
        AND p.CreationDate BETWEEN DATE '2021-01-01' AND DATE '2023-12-31'
        AND (p.Tags LIKE '%<java>%' OR p.Tags LIKE '%<c#>%')
),
PostUpvoteCounts AS (
    SELECT
        v.PostId,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpvoteCount
    FROM Votes v
    WHERE v.VoteTypeId = 2
    GROUP BY v.PostId
),
LinkedPostDetails AS (
    SELECT
        pl.PostId,
        STRING_AGG(CASE WHEN lt.Name = 'Linked' THEN 'L:' || CAST(pl.RelatedPostId AS VARCHAR) ELSE 'D:' || CAST(pl.RelatedPostId AS VARCHAR) END, '; ') AS RelatedPostsSummary,
        COUNT(CASE WHEN lt.Name = 'Duplicate' THEN 1 END) AS DuplicateLinkCount
    FROM
        PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY
        pl.PostId
),
RecentPostHistorySummary AS (
    SELECT
        ph.PostId,
        MAX(ph.CreationDate) AS LastHistoryDate,
        COALESCE(SUM(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END), 0) AS EditCount,
        STRING_AGG(DISTINCT COALESCE(ph.UserDisplayName, u.DisplayName), ', ') AS LastKnownEditors
    FROM
        PostHistory ph
    LEFT JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4,5,6,10,11,12,13)
    GROUP BY ph.PostId
)
SELECT
    pca.PostId,
    pca.PostTypeId,
    pt.Name AS PostTypeName,
    uas.UserDisplayName AS OwnerName,
    uas.Reputation AS OwnerReputation,
    uas.UserGoldBadgeCount AS OwnerTotalGoldBadges,
    pca.PostCreationDate,
    pca.Score,
    pca.ViewCount,
    pca.AnswerCount,
    pca.CommentCount,
    pca.FavoriteCount,
    pca.LastActivityDate,
    pca.ClosedDate,
    pca.Title,
    pca.EffectiveOwnerDisplayName,
    pca.LatestCloseReasonComment,
    pca.PostEngagementCategory,
    pca.BodyLength,
    pca.NumberOfTags,
    pca.ViewsPerScore,
    COALESCE(puc.UpvoteCount, 0) AS UpvoteCount,
    pca.RankInMonthlyPosts,
    lpd.RelatedPostsSummary,
    lpd.DuplicateLinkCount,
    rphs.EditCount AS TotalHistoryEdits,
    rphs.LastKnownEditors,
    (SELECT COUNT(DISTINCT c.Id) FROM Comments c WHERE c.PostId = pca.PostId AND c.CreationDate > (pca.LastActivityDate - INTERVAL '7' DAY)) AS RecentCommentCount,
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = pca.PostId AND v.VoteTypeId = 8) AS AverageBountyAmount,
    (
        SELECT
            ph_inner.Text
        FROM
            PostHistory ph_inner
        WHERE
            ph_inner.PostId = pca.PostId
            AND ph_inner.PostHistoryTypeId = 5
        ORDER BY
            ph_inner.CreationDate DESC
        LIMIT 1
    ) AS LatestBodyEditContent,
    CASE
        WHEN pca.ClosedDate IS NOT NULL AND pca.AcceptedAnswerId IS NULL THEN 'Closed Unresolved'
        WHEN pca.ClosedDate IS NULL AND pca.AcceptedAnswerId IS NOT NULL THEN 'Open Resolved'
        WHEN pca.ClosedDate IS NOT NULL AND pca.AcceptedAnswerId IS NOT NULL THEN 'Closed Resolved'
        ELSE 'Open Unresolved'
    END AS ResolutionStatus,
    pca.BodyExcerpt,
    pca.CleanedTags
FROM
    PostContentAnalysis pca
JOIN PostTypes pt ON pca.PostTypeId = pt.Id
LEFT JOIN UserActivitySummary uas ON pca.OwnerUserId = uas.UserId
LEFT JOIN LinkedPostDetails lpd ON pca.PostId = lpd.PostId
LEFT JOIN RecentPostHistorySummary rphs ON pca.PostId = rphs.PostId
LEFT JOIN PostUpvoteCounts puc ON pca.PostId = puc.PostId
WHERE
    pca.Score > 5
    AND pca.ViewCount > 50
    AND (pca.FavoriteCount IS NULL OR pca.FavoriteCount > 0)
    AND uas.DaysAccountActive > 30
    AND (pca.LatestCloseReasonComment IS NULL OR pca.LatestCloseReasonComment NOT LIKE '%duplicate%')
    AND pca.PostEngagementCategory <> 'General Topic'
ORDER BY
    pca.Score DESC,
    pca.ViewCount DESC,
    pca.LastActivityDate DESC
LIMIT 500;