-- {"query": "1547.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1325} 
WITH RECURSIVE UserActivityLens AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.WebsiteUrl,
        -- String manipulation with NULL fetching user timezone substr if existent, else default index
        COALESCE(SUBSTRING(u.WebsiteUrl FROM '[a-z]+://([a-z0-9\\.-]+)/?'), 'unknown.host') AS HostExtracted,
        -- Calculation example: activity Days and normalized Reputation
        EXTRACT(DAY FROM (CURRENT_TIMESTAMP - u.LastAccessDate)) AS DaysOffline,
        u.Reputation / NULLIF(EXTRACT(YEAR FROM (CURRENT_TIMESTAMP - u.CreationDate)),0) AS AvgReputationPerYear,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS RepRank
    FROM
        Users u
    WHERE
        u.Reputation > 1000
        AND (u.Location IS NOT NULL AND LENGTH(u.Location) > 2)
),
PostAggregate AS (
    SELECT
        p.OwnerUserId AS UserId,
        p.PostTypeId,
        COUNT(*) AS CountPosts,
        SUM(p.Score) AS ScoreSum,
        SUM(p.ViewCount) AS ViewsSum,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        AVG(LENGTH(COALESCE(p.Body, '')) - LENGTH(REPLACE(COALESCE(p.Body, ''), '<p>', ''))) AS AvgParagraphCountBody,
         -- Regular expressions to count occurrences of links relative to body content length
        CASE WHEN LENGTH(COALESCE(p.Body, '')) > 0 THEN CAST(REGEXP_COUNT(lower(p.Body) , 'href="http') AS FLOAT)/ LENGTH(p.Body) ELSE NULL END AS LinksDensity
    FROM
        Posts p
    WHERE
        p.OwnerUserId > 0
    GROUP BY
        p.OwnerUserId,
        p.PostTypeId
),
BadgeRanked AS (
    SELECT 
        b.UserId,
        b.Name,
        b.Class,
        CONCAT(b.Name, CASE b.TagBased WHEN 1 THEN '(tag)' ELSE '(non-tag)' END) AS FullBadgeName,
        DENSE_RANK() OVER (PARTITION BY b.UserId ORDER BY b.Class ASC, b.Date DESC) AS BadgeRank
    FROM 
        Badges b
),
UserInteractLeft AS (
    SELECT
        ua.UserId,
        plc.PostId,
        MAX(plc.CreationDate) AS LastLinkDate,
        COUNT(DISTINCT pl.RelatedPostId) AS DuplicateLinksCount
    FROM
        Votes plc 
        LEFT JOIN PostLinks pl ON plc.PostId = pl.PostId AND pl.LinkTypeId = 3 
        JOIN Posts p ON plc.PostId = p.Id
        JOIN Users ua ON ua.Id = p.OwnerUserId
    WHERE
        plc.VoteTypeId = 2 --upvotes as proxy for interaction
    GROUP BY
        ua.UserId,
        plc.PostId
),
RecentCommentsFlag AS (
    SELECT DISTINCT
        -- Existence correlated subquery filtering comments on user's posts stupifying recency, taga upside conjunction,
        u.Id AS UserId,
        EXISTS (
            SELECT 1 FROM Comments c 
            WHERE c.UserId = u.Id AND c.CreationDate > (CURRENT_TIMESTAMP - INTERVAL '30 days')
                AND EXISTS (SELECT 1 FROM Posts p_ex WHERE p_ex.Id = c.PostId AND p_ex.OwnerUserId = u.Id)
        ) CONNECTION_RECENT
    FROM Users u
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Location,
    ua.HostExtracted,
    s.CountPosts AS TotalPosts,
    s.ScoreSum AS TotalScore,
    COALESCE((SELECT SUM(ScoreSum) FROM PostAggregate pa2 WHERE pa2.UserId = ua.UserId AND pa2.PostTypeId = 1),0) AS QuestionScore,
    COALESCE((SELECT SUM(ScoreSum) FROM PostAggregate pa3 WHERE pa3.UserId = ua.UserId AND pa3.PostTypeId = 2),0) AS AnswerScore,
    br.BadgeSumEuro,
    STRING_AGG(DISTINCT CAST(CONCAT_WS(':', br.FirstBadgeName, br.FirstBadgeClass) AS text), '; ' ORDER BY br.FirstBadgeClass NULLS LAST) AS TopBadges,
    CASE WHEN rec.CONNECTION_RECENT THEN 'Active in Recent 30d Comments' ELSE 'No recent commenting' END AS RecentCommentingStatus,
    uil.DuplicateLinksCount,
    ROW_NUMBER() OVER(PARTITION BY 1 ORDER BY ua.Reputation DESC NULLS LAST) AS UserGlobalRank
FROM 
    UserActivityLens ua
LEFT JOIN 
    (SELECT UserId, 
        COUNT(*) FILTER (WHERE Class=1) * 50 + COUNT(*) FILTER (WHERE Class=2) * 20 + COUNT(*) FILTER (WHERE Class=3) * 5 AS BadgeSumEuro,
        MIN(Name) AS FirstBadgeName,
        MIN(Class) AS FirstBadgeClass
     FROM Badges GROUP BY UserId) br ON br.UserId=ua.UserId
LEFT JOIN 
    (SELECT UserId, SUM(CountPosts) AS CountPosts, SUM(ScoreSum) AS ScoreSum FROM PostAggregate GROUP BY UserId) s 
    ON s.UserId = ua.UserId
LEFT JOIN
    UserInteractLeft uil ON uil.UserId = ua.UserId
LEFT JOIN
    RecentCommentsFlag rec ON rec.UserId = ua.UserId
WHERE
    ua.AvgReputationPerYear > 50
    AND ua.DaysOffline < 365
ORDER BY UserGlobalRank DESC
LIMIT 10
UNION ALL
SELECT
    -1 AS UserId,
    'Anonymous User' AS DisplayName,
    NULL AS Location,
    NULL AS HostExtracted, 
    0 AS TotalPosts,
    0 AS TotalScore,
    0 AS QuestionScore,
    0 AS AnswerScore,
    0 AS BadgeSumEuro,
    'No Badges' AS TopBadges,
    'No recent commenting' AS RecentCommentingStatus,
    0 AS DuplicateLinksCount,
    999999 AS UserGlobalRank
ORDER BY UserGlobalRank
;