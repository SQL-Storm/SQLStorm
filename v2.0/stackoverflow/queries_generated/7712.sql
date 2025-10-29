-- {"query": "7712.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2065} 
WITH UserActivitySummary AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        COUNT(DISTINCT c.Id) AS Comments,
        COUNT(DISTINCT b.Id) AS Badges,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        DENSE_RANK() OVER (ORDER BY u.Views DESC) AS ViewRank,
        RANK() OVER (ORDER BY u.UpVotes - u.DownVotes DESC) AS VoteRank,
        NTILE(10) OVER (ORDER BY u.Reputation) AS ReputationDecile
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.AccountId IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostPerformance AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1
            WHEN p.PostTypeId = 2 AND p.ParentId IS NOT NULL THEN 2
            ELSE 0
        END AS PostStatus,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'High'
            WHEN p.ViewCount > 100 THEN 'Medium'
            WHEN p.ViewCount > 0 THEN 'Low'
            ELSE 'None'
        END AS ViewCategory,
        DATEDIFF('DAY', p.CreationDate, p.LastActivityDate) AS AgeInDays,
        CASE 
            WHEN p.PostTypeId = 1 AND p.Score > 100 THEN 'HotQuestion'
            WHEN p.PostTypeId = 2 AND p.Score > 50 THEN 'HotAnswer'
            ELSE 'Regular'
        END AS PopularityLevel,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousScore,
        LAG(p.ViewCount, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousViews
    FROM Posts p
    WHERE p.CreationDate >= '2020-01-01'
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count AS TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        CASE 
            WHEN t.Count > 1000 THEN 'Trending'
            WHEN t.Count > 100 THEN 'Popular'
            WHEN t.Count > 10 THEN 'Moderate'
            ELSE 'Niche'
        END AS TagPopularity,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank,
        AVG(t.Count) OVER () AS AvgTagCount
    FROM Tags t
),
UserEngagementMetrics AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId IN (2, 3) THEN v.PostId END) AS VoteCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.PostId END) AS FavoriteCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId IN (8, 9) THEN v.Id END) AS BountyCount,
        AVG(v.BountyAmount) AS AvgBountyAmount,
        STRING_AGG(DISTINCT vt.Name, ', ') AS VoteTypes,
        STRING_AGG(DISTINCT CASE WHEN v.VoteTypeId IN (2, 3) THEN p.Title END, ' | ') AS VotedPosts
    FROM Users u
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    LEFT JOIN Posts p ON v.PostId = p.Id
    WHERE v.CreationDate >= '2020-01-01'
    GROUP BY u.Id, u.DisplayName
)
SELECT DISTINCT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.Views,
    uas.UpVotes,
    uas.DownVotes,
    uas.TotalPosts,
    uas.Questions,
    uas.Answers,
    uas.Comments,
    uas.Badges,
    uas.ReputationRank,
    uas.ViewRank,
    uas.VoteRank,
    uas.ReputationDecile,
    pm.PostId,
    pm.Title,
    pm.Score,
    pm.ViewCount,
    pm.AnswerCount,
    pm.CommentCount,
    pm.FavoriteCount,
    pm.PostStatus,
    pm.ViewCategory,
    pm.AgeInDays,
    pm.PopularityLevel,
    pm.PreviousScore,
    pm.PreviousViews,
    ta.TagName,
    ta.TagCount,
    ta.TagPopularity,
    ta.TagRank,
    ta.AvgTagCount,
    uem.VoteCount,
    uem.FavoriteCount,
    uem.BountyCount,
    uem.AvgBountyAmount,
    CASE 
        WHEN uas.Reputation > 100000 AND uas.Views > 10000 THEN 'Elite'
        WHEN uas.Reputation > 10000 AND uas.Views > 1000 THEN 'Active'
        WHEN uas.Reputation > 1000 THEN 'Regular'
        ELSE 'Newbie'
    END AS UserTier,
    CASE 
        WHEN pm.AgeInDays > 365 AND pm.Score >= 0 THEN 'Longevity'
        WHEN pm.AgeInDays <= 365 AND pm.Score >= 50 THEN 'CurrentHot'
        WHEN pm.ViewCount > 1000 THEN 'Viral'
        ELSE 'Regular'
    END AS PostLifecycle,
    CASE 
        WHEN ta.TagCount > (ta.AvgTagCount * 2) THEN 'Overperforming'
        WHEN ta.TagCount > ta.AvgTagCount THEN 'AboveAverage'
        WHEN ta.TagCount > (ta.AvgTagCount / 2) THEN 'BelowAverage'
        ELSE 'Underperforming'
    END AS TagPerformance,
    COALESCE(pm.Score, 0) + COALESCE(pm.ViewCount, 0) + COALESCE(pm.AnswerCount, 0) AS CompositeMetric,
    DENSE_RANK() OVER (ORDER BY (COALESCE(pm.Score, 0) + COALESCE(pm.ViewCount, 0) + COALESCE(pm.AnswerCount, 0)) DESC) AS CompositeRank,
    ROW_NUMBER() OVER (ORDER BY uas.Reputation DESC, pm.Score DESC) AS CombinedRank,
    CONCAT('User-', uas.UserId, '-Post-', pm.PostId, '-Tag-', ta.TagName) AS UniqueIdentifier,
    CASE 
        WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = pm.PostId AND pl.LinkTypeId = 3) THEN 'DuplicatePost'
        WHEN EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId = pm.PostId AND ph.PostHistoryTypeId = 10) THEN 'ClosedPost'
        ELSE 'Active'
    END AS PostStatusAnalysis
FROM UserActivitySummary uas
INNER JOIN PostPerformance pm ON uas.UserId = pm.OwnerUserId
LEFT JOIN Tags t ON (pm.Tags IS NOT NULL AND LENGTH(pm.Tags) > 0 AND t.TagName IN (
    SELECT TRIM(SUBSTRING(pm.Tags, pos, 
        CASE 
            WHEN CHARINDEX('>', pm.Tags, pos) > 0 THEN CHARINDEX('>', pm.Tags, pos) - pos
            ELSE LENGTH(pm.Tags) - pos + 1
        END
    )) 
    FROM (SELECT 1 AS pos UNION SELECT 5 UNION SELECT 10 UNION SELECT 15 UNION SELECT 20 UNION SELECT 25) numbers
    WHERE pos <= LENGTH(pm.Tags) 
    AND SUBSTRING(pm.Tags, pos, 1) = '<'
))
LEFT JOIN TagAnalysis ta ON t.TagName = ta.TagName
LEFT JOIN UserEngagementMetrics uem ON uas.UserId = uem.UserId
WHERE uas.UserId IS NOT NULL
  AND (pm.Score IS NOT NULL OR pm.ViewCount IS NOT NULL OR pm.AnswerCount IS NOT NULL)
  AND (CASE WHEN pm.Score IS NOT NULL THEN pm.Score ELSE 0 END) + 
      (CASE WHEN pm.ViewCount IS NOT NULL THEN pm.ViewCount ELSE 0 END) + 
      (CASE WHEN pm.AnswerCount IS NOT NULL THEN pm.AnswerCount ELSE 0 END) > 0
  AND NOT (uas.UserId = 0 AND pm.PostId IS NULL AND ta.TagName IS NULL)
ORDER BY uas.Reputation DESC, 
         (COALESCE(pm.Score, 0) + COALESCE(pm.ViewCount, 0) + COALESCE(pm.AnswerCount, 0)) DESC,
         uas.ViewRank,
         uas.VoteRank
LIMIT 1000;