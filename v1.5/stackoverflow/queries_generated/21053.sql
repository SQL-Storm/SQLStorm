-- {"query": "21053.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2168, "output_tokens": 1207} 

WITH ActiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.UpVotes + u.DownVotes AS TotalVotes,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY u.Reputation DESC) AS RepRankByYear
    FROM Users u
    WHERE u.Reputation > 1000
      AND u.LastAccessDate > CURRENT_TIMESTAMP - INTERVAL '1 year'
),
QuestionStats AS (
    SELECT 
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.CreationDate AS QuestionDate,
        p.Score AS QuestionScore,
        p.ViewCount,
        p.AnswerCount,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community'
            ELSE 'Open'
        END AS Status,
        LENGTH(p.Title) AS TitleLength,
        LENGTH(REGEXP_REPLACE(p.Tags, '<[^>]+>', '', 'g')) AS TagLength,
        AVG(v.BountyAmount) OVER (PARTITION BY EXTRACT(YEAR FROM p.CreationDate)) AS AvgBountyYear
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8
    WHERE p.PostTypeId = 1
      AND p.CreationDate > CURRENT_TIMESTAMP - INTERVAL '5 years'
),
TopBadges AS (
    SELECT 
        b.UserId,
        b.Name AS BadgeName,
        b.Date AS BadgeDate,
        b.Class,
        COUNT(*) OVER (PARTITION BY b.UserId) AS TotalBadgesUser,
        DENSE_RANK() OVER (ORDER BY COUNT(*) DESC) AS BadgePopularityRank
    FROM Badges b
    WHERE b.TagBased = FALSE
      AND b.Date > CURRENT_TIMESTAMP - INTERVAL '3 years'
    GROUP BY b.UserId, b.Name, b.Date, b.Class
    HAVING COUNT(*) > 1
),
LinkNetwork AS (
    SELECT 
        pl.PostId,
        pl.RelatedPostId,
        pl.LinkTypeId,
        COUNT(pl.Id) OVER (PARTITION BY pl.PostId) AS OutboundLinks,
        COUNT(pl.Id) OVER (PARTITION BY pl.RelatedPostId) AS InboundLinks
    FROM PostLinks pl
    WHERE pl.CreationDate > CURRENT_TIMESTAMP - INTERVAL '2 years'
)
SELECT 
    au.UserId,
    au.Reputation,
    au.RepRankByYear,
    qs.QuestionId,
    qs.QuestionScore * (1.0 + COALESCE(qs.AnswerCount, 0)) AS WeightedScore,
    COALESCE(qs.ViewCount / NULLIF(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - qs.QuestionDate)) / 86400, 0), 0) AS ViewsPerDay,
    CASE 
        WHEN qs.Status = 'Closed' AND qs.ClosedDate IS NOT NULL 
        THEN EXTRACT(DAY FROM (qs.ClosedDate - qs.QuestionDate))
        ELSE NULL
    END AS DaysToClose,
    CONCAT(
        UPPER(SUBSTRING(qs.Title FROM 1 FOR 1)), 
        LOWER(SUBSTRING(qs.Title FROM 2 FOR 50))
    ) AS TitleSnippet,
    tb.BadgeName,
    tb.TotalBadgesUser,
    COALESCE(ln.OutboundLinks, 0) + COALESCE(ln.InboundLinks, 0) AS TotalConnections,
    STRING_AGG(
        DISTINCT COALESCE(c.Text, ''), 
        ' | ' ORDER BY c.CreationDate
    ) OVER (PARTITION BY qs.QuestionId ORDER BY c.CreationDate ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS RecentComments,
    (SELECT AVG(ph.CreationDate) 
     FROM PostHistory ph 
     WHERE ph.PostId = qs.QuestionId 
       AND ph.PostHistoryTypeId IN (4, 5, 6)  -- Edits
     GROUP BY ph.PostId
    ) AS AvgEditTime,
    GREATEST(
        COALESCE(qs.AvgBountyYear, 0),
        COALESCE(au.TotalVotes * 0.1, 0),
        COALESCE(tb.BadgePopularityRank * 10, 0)
    ) AS CompositeScore
FROM ActiveUsers au
INNER JOIN QuestionStats qs ON au.UserId = qs.OwnerUserId
LEFT JOIN TopBadges tb ON au.UserId = tb.UserId AND tb.BadgeDate > qs.QuestionDate - INTERVAL '1 year'
LEFT JOIN LinkNetwork ln ON qs.QuestionId = ln.PostId OR qs.QuestionId = ln.RelatedPostId
LEFT JOIN Comments c ON qs.QuestionId = c.PostId AND c.CreationDate > qs.QuestionDate
WHERE au.RepRankByYear <= 50
  AND (qs.Status != 'Closed' OR (qs.Status = 'Closed' AND qs.DaysToClose < 30))
  AND NOT (qs.TagLength IS NULL OR qs.TagLength = 0)
GROUP BY 
    au.UserId, au.Reputation, au.RepRankByYear,
    qs.QuestionId, qs.QuestionScore, qs.AnswerCount, qs.ViewCount, 
    qs.QuestionDate, qs.ClosedDate, qs.Status, qs.Title, qs.Tags, 
    qs.FavoriteCount, qs.AvgBountyYear,
    tb.BadgeName, tb.TotalBadgesUser, tb.BadgePopularityRank,
    ln.OutboundLinks, ln.InboundLinks
HAVING COUNT(DISTINCT tb.BadgeName) > 0 OR qs.AnswerCount > 5
ORDER BY CompositeScore DESC, ViewsPerDay DESC
LIMIT 1000;
