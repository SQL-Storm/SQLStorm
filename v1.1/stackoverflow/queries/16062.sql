WITH UserEngagementMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.Location,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) AS QuestionScore,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) AS AnswerScore,
        ROW_NUMBER() OVER (PARTITION BY COALESCE(SUBSTRING(u.Location FROM 1 FOR 20), 'Unknown') ORDER BY u.Reputation DESC) AS LocationRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT b.Id) DESC) AS BadgeRank,
        LAG(u.Reputation, 1, 0) OVER (ORDER BY u.CreationDate) AS PrevUserReputation,
        LEAD(u.Reputation, 1, 0) OVER (ORDER BY u.CreationDate) AS NextUserReputation,
        u.CreationDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.CreationDate >= DATE '2020-01-01'
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3)
    WHERE u.Reputation > 100
      AND (u.Location IS NOT NULL OR u.WebsiteUrl IS NOT NULL)
      AND u.CreationDate >= DATE '2015-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) > 0
),
ComplexPostAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        COALESCE(LENGTH(p.Body), 0) AS BodyLength,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN p.AnswerCount > 0 THEN 'Has Answers'
            ELSE 'Open'
        END AS PostStatus,
        COALESCE(u.DisplayName, p.OwnerDisplayName, 'Anonymous') AS AuthorName,
        STRING_AGG(DISTINCT COALESCE(c.Text, ''), ' | ') AS ConcatenatedComments,
        (SELECT COUNT(*) 
         FROM PostHistory ph 
         WHERE ph.PostId = p.Id 
           AND ph.PostHistoryTypeId IN (4, 5, 6)
        ) AS EditCount,
        (SELECT COALESCE(AVG(v2.BountyAmount), 0)
         FROM Votes v2
         WHERE v2.PostId = p.Id 
           AND v2.VoteTypeId = 8
        ) AS AvgBounty,
        EXTRACT(EPOCH FROM (COALESCE(p.LastActivityDate, p.CreationDate) - p.CreationDate)) / 86400.0 AS DaysActive,
        CASE 
            WHEN p.Tags LIKE '%<sql>%' THEN 1
            WHEN p.Tags LIKE '%<python>%' THEN 2
            WHEN p.Tags LIKE '%<javascript>%' THEN 3
            ELSE 0
        END AS PrimaryTagCategory,
        p.Body,
        p.ClosedDate,
        p.AcceptedAnswerId,
        u.DisplayName AS UserDisplayName,
        p.OwnerDisplayName,
        p.LastActivityDate,
        p.CreationDate,
        p.Tags
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId AND c.Score > 0
    WHERE p.PostTypeId IN (1, 2)
      AND p.CreationDate BETWEEN DATE '2019-01-01' AND DATE '2023-12-31'
      AND (p.Score > 5 OR p.ViewCount > 1000 OR COALESCE(p.FavoriteCount, 0) > 0)
    GROUP BY p.Id, p.Title, p.PostTypeId, p.Score, p.ViewCount, p.AnswerCount, 
             p.Body, p.ClosedDate, p.AcceptedAnswerId, u.DisplayName, 
             p.OwnerDisplayName, p.LastActivityDate, p.CreationDate, p.Tags
),
TagPopularity AS (
    SELECT 
        t.TagName,
        t.Count,
        COUNT(DISTINCT pl.PostId) AS LinkedPostCount,
        AVG(p.Score) AS AvgTagScore,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.ViewCount) AS MedianViews,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN p.Id END) * 100.0 / NULLIF(COUNT(DISTINCT p.Id), 0) AS AcceptanceRate,
        t.IsModeratorOnly
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    WHERE t.Count > 100
      AND (t.IsModeratorOnly = FALSE OR t.IsModeratorOnly = CAST(0 AS BOOLEAN))
    GROUP BY t.TagName, t.Count, t.IsModeratorOnly
)
SELECT 
    uem.DisplayName,
    COALESCE(NULLIF(TRIM(uem.Location), ''), 'Not Specified') AS CleanedLocation,
    uem.Reputation,
    uem.PostCount,
    uem.BadgeCount,
    uem.QuestionScore + uem.AnswerScore AS TotalScore,
    ROUND(CASE WHEN uem.AnswerScore = 0 THEN NULL ELSE CAST(uem.QuestionScore AS NUMERIC) / NULLIF(uem.AnswerScore, 0) END, 2) AS QuestionAnswerRatio,
    cpa.PostStatus,
    COUNT(DISTINCT cpa.PostId) AS AnalyzedPosts,
    AVG(cpa.BodyLength) AS AvgBodyLength,
    SUM(cpa.ViewCount) AS TotalViews,
    MAX(cpa.AvgBounty) AS MaxBounty,
    STRING_AGG(DISTINCT tp.TagName, ', ') FILTER (WHERE tp.Count > 500) AS PopularTags,
    CASE 
        WHEN uem.LocationRank <= 3 THEN 'Top in Location'
        WHEN uem.BadgeRank <= 100 THEN 'Badge Leader'
        WHEN uem.Reputation > 10000 THEN 'High Rep'
        ELSE 'Regular User'
    END AS UserTier,
    ROUND(AVG(cpa.DaysActive) FILTER (WHERE cpa.DaysActive > 0), 2) AS AvgPostLifespanDays,
    (SELECT COUNT(*) FROM Votes v 
     WHERE v.UserId = uem.Id 
       AND v.VoteTypeId = 2 
       AND v.CreationDate > (DATE '2024-10-01' - INTERVAL '365 days')
    ) AS RecentUpvotes
FROM UserEngagementMetrics uem
INNER JOIN ComplexPostAnalysis cpa ON cpa.AuthorName = uem.DisplayName
LEFT JOIN Posts p2 ON p2.OwnerUserId = uem.Id AND p2.PostTypeId = 1
LEFT JOIN TagPopularity tp ON p2.Tags LIKE '%' || '<' || tp.TagName || '>' || '%' AND tp.AcceptanceRate > 50
WHERE uem.LocationRank <= 10
  AND cpa.EditCount < 20
  AND (cpa.AvgBounty > 0 OR cpa.PrimaryTagCategory IN (1, 2))
  AND NOT EXISTS (
      SELECT 1 
      FROM Votes v3 
      WHERE v3.UserId = uem.Id 
        AND v3.VoteTypeId = 12
      GROUP BY v3.UserId
      HAVING COUNT(*) > 5
  )
GROUP BY uem.Id, uem.DisplayName, uem.Location, uem.Reputation, uem.PostCount, 
         uem.BadgeCount, uem.QuestionScore, uem.AnswerScore, uem.LocationRank, 
         uem.BadgeRank, cpa.PostStatus
HAVING COUNT(DISTINCT cpa.PostId) >= 2
  AND SUM(cpa.ViewCount) > 1000
ORDER BY TotalScore DESC, uem.Reputation DESC, AvgBodyLength DESC
LIMIT 500;