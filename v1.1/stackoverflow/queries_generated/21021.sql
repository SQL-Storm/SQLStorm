-- {"query": "21021.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2168, "output_tokens": 1337} 

WITH ActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation,
           COUNT(DISTINCT p.Id) AS QuestionCount,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.DeletedDate IS NULL
    LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (2, 3) -- Upvotes and downvotes
    WHERE u.Reputation > 1000
      AND u.CreationDate >= NOW() - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 5
),
HighImpactPosts AS (
    SELECT p.Id, p.Title, p.Score, p.ViewCount,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC, p.Score DESC) AS ViewRank,
           LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevPostScore,
           COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) AS EngagementScore
    FROM Posts p
    WHERE p.PostTypeId = 1 
      AND p.CreationDate >= NOW() - INTERVAL '1 year'
      AND p.ViewCount > 1000
      AND (p.Tags LIKE '%sql%' OR p.Tags LIKE '%database%' OR p.Tags LIKE '%performance%')
),
RecentEdits AS (
    SELECT ph.PostId, ph.UserId, 
           COUNT(*) OVER (PARTITION BY ph.PostId) AS EditCount,
           STRING_AGG(ph.Comment, ' | ') AS EditComments,
           MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Title, Body, Tags edits
      AND ph.CreationDate >= NOW() - INTERVAL '6 months'
    GROUP BY ph.PostId, ph.UserId
),
ComplexTags AS (
    SELECT t.TagName, t.Count, 
           CASE 
               WHEN t.Count > 10000 THEN 'Popular'
               WHEN t.Count BETWEEN 1000 AND 10000 THEN 'Growing'
               ELSE 'Niche'
           END AS TagCategory,
           AVG(t.Count) OVER () AS AvgTagCount
    FROM Tags t
    WHERE t.Count > 0
)
SELECT 
    au.DisplayName AS UserName,
    au.Reputation,
    au.QuestionCount,
    au.TotalUpvotes,
    hp.Title,
    hp.Score AS PostScore,
    hp.ViewCount,
    hp.ViewRank,
    hp.EngagementScore,
    re.EditCount,
    COALESCE(ct.TagCategory, 'No Category') AS TagCategory,
    CASE 
        WHEN hp.ViewRank = 1 AND hp.ViewCount > (SELECT AVG(ViewCount) FROM HighImpactPosts WHERE OwnerUserId = au.Id) * 2 
        THEN 'High Impact'
        WHEN re.EditCount > 3 THEN 'Frequently Edited'
        WHEN hp.Score < 0 OR hp.ViewRank > 5 THEN 'Underperforming'
        ELSE 'Average'
    END AS PostPerformanceCategory,
    GREATEST(hp.Score, COALESCE(au.Reputation / 100.0, 0)) AS WeightedScore,
    NULLIF(hp.Title, '') IS NULL OR LENGTH(TRIM(COALESCE(hp.Title, ''))) = 0 AS HasEmptyTitle,
    (SELECT STRING_AGG(b.Name, ', ') 
     FROM Badges b 
     WHERE b.UserId = au.Id 
       AND b.Class = 1  -- Gold badges only
       AND b.Date >= NOW() - INTERVAL '1 year'
    ) AS RecentGoldBadges,
    (SELECT COUNT(DISTINCT pl.RelatedPostId)
     FROM PostLinks pl
     INNER JOIN HighImpactPosts hp2 ON pl.RelatedPostId = hp2.Id
     WHERE pl.PostId = hp.Id 
       AND pl.LinkTypeId = 1  -- Linked posts
       AND pl.CreationDate >= NOW() - INTERVAL '3 months'
    ) AS ExternalLinksCount
FROM ActiveUsers au
INNER JOIN HighImpactPosts hp ON hp.OwnerUserId = au.Id
LEFT JOIN RecentEdits re ON re.PostId = hp.Id
LEFT JOIN Tags ct ON ct.TagName = ANY(STRING_TO_ARRAY(SUBSTRING(hp.Tags FROM 2 FOR LENGTH(hp.Tags)-2), '><'))
LEFT JOIN ComplexTags ON ct.TagCategory IS NOT NULL
WHERE hp.ViewRank <= 3
  AND (hp.CreationDate >= NOW() - INTERVAL '3 months' OR hp.LastActivityDate >= NOW() - INTERVAL '1 month')
  AND NOT EXISTS (
      SELECT 1 FROM PostHistory ph2 
      WHERE ph2.PostId = hp.Id 
        AND ph2.PostHistoryTypeId = 12  -- Post Deleted
        AND ph2.CreationDate > hp.CreationDate
  )
  AND (au.QuestionCount > (SELECT AVG(QuestionCount) FROM ActiveUsers) 
       OR hp.EngagementScore > 50)
UNION ALL
SELECT 
    'Community Average' AS UserName,
    AVG(au.Reputation) AS Reputation,
    AVG(au.QuestionCount)::INT AS QuestionCount,
    SUM(au.TotalUpvotes)::INT AS TotalUpvotes,
    'Overall Stats' AS Title,
    AVG(hp.Score) AS PostScore,
    AVG(hp.ViewCount)::INT AS ViewCount,
    NULL AS ViewRank,
    AVG(hp.EngagementScore)::INT AS EngagementScore,
    AVG(re.EditCount)::INT AS EditCount,
    'All Categories' AS TagCategory,
    'Summary' AS PostPerformanceCategory,
    AVG(GREATEST(hp.Score, COALESCE(au.Reputation / 100.0, 0))) AS WeightedScore,
    FALSE AS HasEmptyTitle,
    NULL AS RecentGoldBadges,
    NULL AS ExternalLinksCount
FROM ActiveUsers au
INNER JOIN HighImpactPosts hp ON hp.OwnerUserId = au.Id
LEFT JOIN RecentEdits re ON re.PostId = hp.Id
ORDER BY UserName, PostScore DESC NULLS LAST;
