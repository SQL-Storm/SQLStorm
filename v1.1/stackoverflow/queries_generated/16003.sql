-- {"query": "16003.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 9340, "output_tokens": 8965} 

WITH RECURSIVE UserEngagementMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS NetVotes,
        EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate)) / 86400.0 AS DaysActive,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
        AND u.LastAccessDate >= CURRENT_DATE - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.UpVotes, u.DownVotes, u.LastAccessDate
),
PostPerformance AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN p.AnswerCount > 0 THEN 'Unanswered'
            ELSE 'No Activity'
        END AS PostStatus,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC NULLS LAST) AS UserPostRank,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgUserScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.ViewCount) OVER (PARTITION BY EXTRACT(YEAR FROM p.CreationDate)) AS MedianYearlyViews,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore,
        LEAD(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) - p.CreationDate AS TimeTillNextPost,
        (SELECT COUNT(*)
         FROM Comments c
         WHERE c.PostId = p.Id
           AND c.Score > 0) AS PositiveComments,
        (SELECT STRING_AGG(DISTINCT t.TagName, ', ')
         FROM LATERAL (
             SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
         ) AS split_tags
         JOIN Tags t ON t.TagName = split_tags.tag
         WHERE t.Count > 1000) AS PopularTags
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '3 years'
        AND p.OwnerUserId IS NOT NULL
),
VotePatterns AS (
    SELECT 
        v.PostId,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 5) AS Favorites,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 8) AS BountyStarts,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN COALESCE(v.BountyAmount, 0) ELSE 0 END) AS TotalBountyAmount,
        MAX(v.CreationDate) AS LastVoteDate,
        ARRAY_AGG(DISTINCT v.VoteTypeId ORDER BY v.VoteTypeId) AS VoteTypeArray
    FROM Votes v
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '3 years'
    GROUP BY v.PostId
),
EditHistory AS (
    SELECT 
        ph.PostId,
        COUNT(DISTINCT ph.UserId) AS UniqueEditors,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6)) AS EditCount,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseVoteCount,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment ELSE NULL END) AS LastCloseReason,
        STRING_AGG(DISTINCT COALESCE(ph.UserDisplayName, 'Anonymous'), ' | ' ORDER BY COALESCE(ph.UserDisplayName, 'Anonymous')) AS EditorNames,
        EXTRACT(EPOCH FROM (MAX(ph.CreationDate) - MIN(ph.CreationDate))) / 3600.0 AS HoursFromFirstToLastEdit
    FROM PostHistory ph
    WHERE ph.CreationDate >= CURRENT_DATE - INTERVAL '3 years'
    GROUP BY ph.PostId
)
SELECT 
    uem.DisplayName,
    uem.Reputation,
    uem.NetVotes,
    ROUND(uem.DaysActive::numeric, 2) AS DaysActive,
    uem.GoldBadges || 'G/' || uem.SilverBadges || 'S/' || uem.BronzeBadges || 'B' AS BadgeBreakdown,
    pp.PostId,
    COALESCE(pt.Name, 'Unknown') AS PostType,
    pp.PostStatus,
    pp.Score AS PostScore,
    COALESCE(pp.ViewCount, 0) AS Views,
    pp.UserPostRank,
    ROUND(pp.AvgUserScore::numeric, 2) AS AvgUserScore,
    pp.MedianYearlyViews,
    pp.PreviousPostScore,
    EXTRACT(DAYS FROM pp.TimeTillNextPost) AS DaysToNextPost,
    pp.PositiveComments,
    COALESCE(pp.PopularTags, 'No Popular Tags') AS PopularTags,
    COALESCE(vp.UpVotes, 0) AS PostUpVotes,
    COALESCE(vp.DownVotes, 0) AS PostDownVotes,
    COALESCE(vp.Favorites, 0) AS PostFavorites,
    COALESCE(vp.TotalBountyAmount, 0) AS BountyValue,
    COALESCE(eh.EditCount, 0) AS EditCount,
    COALESCE(eh.UniqueEditors, 0) AS UniqueEditors,
    COALESCE(eh.EditorNames, 'No Edits') AS Editors,
    ROUND(COALESCE(eh.HoursFromFirstToLastEdit, 0)::numeric, 2) AS EditingDuration,
    CASE 
        WHEN pp.Score > pp.AvgUserScore * 1.5 THEN 'Exceptional'
        WHEN pp.Score > pp.AvgUserScore THEN 'Above Average'
        WHEN pp.Score = pp.AvgUserScore THEN 'Average'
        ELSE 'Below Average'
    END AS PerformanceCategory,
    DENSE_RANK() OVER (ORDER BY uem.Reputation DESC, uem.GoldBadges DESC) AS GlobalUserRank,
    NTILE(10) OVER (ORDER BY pp.Score DESC NULLS LAST) AS ScoreDecile,
    (SELECT COUNT(DISTINCT pl.RelatedPostId)
     FROM PostLinks pl
     WHERE pl.PostId = pp.PostId
       AND pl.LinkTypeId = 1) AS LinkedPostCount,
    EXISTS (
        SELECT 1 
        FROM PostLinks pl2 
        WHERE pl2.PostId = pp.PostId 
          AND pl2.LinkTypeId = 3
    ) AS IsDuplicate
FROM UserEngagementMetrics uem
INNER JOIN PostPerformance pp ON uem.Id = pp.OwnerUserId
LEFT OUTER JOIN VotePatterns vp ON pp.PostId = vp.PostId
LEFT OUTER JOIN EditHistory eh ON pp.PostId = eh.PostId
LEFT OUTER JOIN PostTypes pt ON pp.PostTypeId = pt.Id
WHERE pp.UserPostRank <= 10
    AND (pp.Score >= 5 OR pp.ViewCount > 100 OR vp.TotalBountyAmount > 0)
    AND (eh.EditCount IS NULL OR eh.EditCount < 20)
    AND COALESCE(vp.UpVotes, 0) - COALESCE(vp.DownVotes, 0) >= -5
    AND (pp.PopularTags IS NOT NULL OR pp.Score > 10)
ORDER BY 
    uem.Reputation DESC,
    pp.Score DESC NULLS LAST,
    pp.ViewCount DESC NULLS LAST,
    pp.UserPostRank
LIMIT 1000;
