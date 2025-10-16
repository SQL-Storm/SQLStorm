-- {"query": "757.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1312} 

WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        1 AS Depth
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT 
        child.Id,
        child.TagName,
        child.Count,
        child.ExcerptPostId,
        child.WikiPostId,
        child.IsModeratorOnly,
        child.IsRequired,
        p.Depth + 1
    FROM Tags child
    JOIN RecursiveTagHierarchy p ON child.Id != p.Id AND child.IsRequired = 1
    WHERE p.Depth < 3
),
UserBadgeSummary AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(DISTINCT CASE WHEN b.TagBased = 1 THEN b.Name ELSE NULL END) AS TagBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
PostActivityWindows AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        p.ParentId,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCountWindow,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS UserPostRank,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgUserPostScore,
        SUM(COALESCE(v.VoteCount, 0)) OVER (PARTITION BY p.OwnerUserId) AS TotalUserVotes
    FROM Posts p
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS VoteCount 
        FROM Votes 
        WHERE VoteTypeId IN (2,3) -- UpMod and DownMod
        GROUP BY PostId
    ) v ON v.PostId = p.Id
    LEFT JOIN Comments c ON c.PostId = p.Id
),
CorrelatedCloseCounts AS (
    SELECT 
        ph.PostId,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseVotes,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 11) AS ReopenVotes
    FROM PostHistory ph
    GROUP BY ph.PostId
),
LatestPostEdits AS (
    SELECT DISTINCT ON (ph.PostId)
        ph.PostId,
        ph.UserId AS EditorUserId,
        ph.UserDisplayName AS EditorName,
        ph.CreationDate AS EditDate,
        ph.Comment,
        ph.PostHistoryTypeId
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6) -- Edits to Title, Body, Tags
    ORDER BY ph.PostId, ph.CreationDate DESC
)
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.Location,
    u.WebsiteUrl,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(ubs.TagBadges, 0) AS TagBadges,
    pa.PostId,
    pa.Title,
    pa.PostTypeId,
    pa.Score,
    pa.ViewCount,
    pa.CommentCountWindow,
    pa.UserPostRank,
    pa.AvgUserPostScore,
    cc.CloseVotes,
    cc.ReopenVotes,
    lpe.EditorName AS LastEditor,
    lpe.EditDate AS LastEditDate,
    CONCAT(
        COALESCE(pa.Tags, ''), ' | Score: ', pa.Score, ' | Views: ', pa.ViewCount, 
        ' | Comments: ', pa.CommentCountWindow, ' | CloseVotes: ', COALESCE(cc.CloseVotes, 0)
    ) AS PostSummary,
    CASE 
        WHEN pa.AcceptedAnswerId IS NOT NULL THEN 'Accepted Answer Present'
        WHEN pa.PostTypeId = 1 AND pa.AcceptedAnswerId IS NULL THEN 'No Accepted Answer'
        ELSE 'N/A'
    END AS AcceptedAnswerStatus,
    -- Complex predicate combining NULL logic and string functions
    CASE 
        WHEN pa.Tags IS NULL THEN 'No Tags'
        WHEN POSITION('sql' IN LOWER(pa.Tags)) > 0 THEN 'Contains SQL Tag'
        ELSE 'Other Tags'
    END AS TagCategory,
    -- Set operator example: simulate IN with EXCEPT to filter users with badges
    EXISTS (
        SELECT 1 FROM Badges b WHERE b.UserId = u.Id EXCEPT SELECT 1 FROM Badges b2 WHERE b2.UserId = u.Id AND b2.Class = 1
    ) AS HasNonGoldBadgesOnly
FROM Users u
LEFT JOIN UserBadgeSummary ubs ON ubs.UserId = u.Id
LEFT JOIN PostActivityWindows pa ON pa.OwnerUserId = u.Id AND pa.UserPostRank <= 3
LEFT JOIN CorrelatedCloseCounts cc ON cc.PostId = pa.PostId
LEFT JOIN LatestPostEdits lpe ON lpe.PostId = pa.PostId
WHERE u.Reputation > (
    SELECT AVG(Reputation) FROM Users WHERE Location IS NOT NULL
)
AND (
    EXISTS (
        SELECT 1 FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.Score > 10
    )
    OR
    u.Id IN (
        SELECT DISTINCT UserId FROM Badges WHERE Name ILIKE '%expert%'
    )
)
ORDER BY u.Reputation DESC, pa.Score DESC NULLS LAST
LIMIT 100;
