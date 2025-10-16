-- {"query": "16044.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 105075, "output_tokens": 98306} 

WITH RECURSIVE UserActivityMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS NetVotes,
        EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate)) / 86400.0 AS DaysActive,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY u.Reputation) OVER () AS MedianReputation
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2020-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes
),
PostPerformance AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 1
            WHEN p.PostTypeId = 2 AND EXISTS (
                SELECT 1 FROM Posts parent 
                WHERE parent.Id = p.ParentId AND parent.AcceptedAnswerId = p.Id
            ) THEN 2
            ELSE 0
        END AS AcceptanceStatus,
        STRING_AGG(DISTINCT SUBSTRING(COALESCE(c.Text, ''), 1, 50), ' | ') AS CommentSample,
        AVG(v.VoteTypeId) FILTER (WHERE v.VoteTypeId IN (2, 3)) AS AvgVoteType,
        COUNT(DISTINCT pl.RelatedPostId) FILTER (WHERE pl.LinkTypeId = 1) AS LinkedCount,
        COUNT(DISTINCT pl.RelatedPostId) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateCount,
        EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 3600.0 AS HoursToLastActivity,
        DENSE_RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC NULLS LAST) AS TypeRank
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId AND c.Score > 0
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.CreationDate >= p.CreationDate
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    WHERE p.CreationDate >= '2019-01-01'
        AND p.OwnerUserId IS NOT NULL
        AND (p.Body IS NULL OR LENGTH(p.Body) > 50)
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount, 
             p.CommentCount, p.CreationDate, p.LastActivityDate, p.ParentId, p.AcceptedAnswerId
),
TagEngagement AS (
    SELECT 
        t.TagName,
        t.Count AS TagUseCount,
        AVG(p.Score) AS AvgPostScore,
        STDDEV_POP(p.Score) AS StdDevScore,
        COUNT(DISTINCT p.OwnerUserId) AS UniqueContributors,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN p.Id END) AS ResolvedQuestions,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY p.ViewCount) AS P75ViewCount,
        ARRAY_AGG(DISTINCT COALESCE(u.Location, 'Unknown') ORDER BY COALESCE(u.Location, 'Unknown')) 
            FILTER (WHERE u.Location IS NOT NULL) AS TopLocations
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%'
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE t.Count > 100
        AND p.PostTypeId = 1
    GROUP BY t.Id, t.TagName, t.Count
    HAVING COUNT(p.Id) > 50
),
HistoryAnalysis AS (
    SELECT 
        ph.PostId,
        COUNT(*) AS TotalEdits,
        COUNT(DISTINCT ph.UserId) AS UniqueEditors,
        MAX(ph.CreationDate) - MIN(ph.CreationDate) AS EditTimespan,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS ContentEdits,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (7, 8, 9) THEN 1 ELSE 0 END) AS Rollbacks,
        CASE 
            WHEN MAX(ph.PostHistoryTypeId) IN (10, 12) THEN 'CLOSED_OR_DELETED'
            WHEN MAX(ph.PostHistoryTypeId) IN (11, 13) THEN 'REOPENED_OR_RESTORED'
            ELSE 'ACTIVE'
        END AS CurrentStatus
    FROM PostHistory ph
    WHERE ph.CreationDate >= '2018-01-01'
    GROUP BY ph.PostId
)
SELECT 
    uam.DisplayName,
    uam.Reputation,
    uam.ReputationRank,
    ROUND(CAST(uam.Reputation AS NUMERIC) / NULLIF(uam.MedianReputation, 0), 2) AS ReputationRatio,
    uam.GoldBadges || 'G/' || uam.SilverBadges || 'S/' || uam.BronzeBadges || 'B' AS BadgeDistribution,
    pp.PostTypeId,
    COUNT(DISTINCT pp.PostId) AS TotalPosts,
    ROUND(AVG(pp.Score), 2) AS AvgScore,
    MAX(pp.Score) AS MaxScore,
    ROUND(AVG(COALESCE(pp.ViewCount, 0)), 0) AS AvgViews,
    SUM(CASE WHEN pp.AcceptanceStatus > 0 THEN 1 ELSE 0 END) AS AcceptedPosts,
    ROUND(AVG(pp.LinkedCount), 2) AS AvgLinkedPosts,
    ROUND(AVG(ha.TotalEdits), 2) AS AvgEditHistory,
    MAX(ha.CurrentStatus) AS PostStatus,
    STRING_AGG(DISTINCT te.TagName, ', ' ORDER BY te.TagName) 
        FILTER (WHERE te.AvgPostScore > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1)) AS HighPerformingTags,
    COALESCE(SUM(pp.CommentCount), 0) AS TotalComments,
    CASE 
        WHEN uam.DaysActive > 0 THEN ROUND(CAST(COUNT(pp.PostId) AS NUMERIC) / uam.DaysActive, 4)
        ELSE NULL
    END AS PostsPerDay,
    RANK() OVER (
        PARTITION BY pp.PostTypeId 
        ORDER BY COUNT(DISTINCT pp.PostId) DESC, AVG(pp.Score) DESC
    ) AS UserTypeRank
FROM UserActivityMetrics uam
INNER JOIN PostPerformance pp ON uam.Id = pp.OwnerUserId
LEFT JOIN HistoryAnalysis ha ON pp.PostId = ha.PostId
LEFT JOIN Posts p ON pp.PostId = p.Id
LEFT JOIN TagEngagement te ON p.Tags LIKE '%<' || te.TagName || '>%'
WHERE pp.TypeRank <= 5000
    AND uam.ReputationRank <= 10000
    AND (pp.Score > 5 OR pp.ViewCount > 100 OR pp.CommentCount > 2)
    AND COALESCE(NULLIF(TRIM(uam.DisplayName), ''), 'Anonymous') <> 'user'
GROUP BY uam.Id, uam.DisplayName, uam.Reputation, uam.ReputationRank, uam.MedianReputation,
         uam.GoldBadges, uam.SilverBadges, uam.BronzeBadges, uam.DaysActive, pp.PostTypeId
HAVING COUNT(DISTINCT pp.PostId) >= 3
    AND AVG(pp.Score) > (SELECT AVG(Score) * 0.5 FROM Posts WHERE Score IS NOT NULL)
ORDER BY uam.Reputation DESC, COUNT(DISTINCT pp.PostId) DESC, AVG(pp.Score) DESC
LIMIT 500;
