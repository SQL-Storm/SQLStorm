-- {"query": "23091.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 901} 
WITH TopQuestions AS (
    SELECT 
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS QuestionRank,
        COALESCE(p.FavoriteCount, 0) AS Favorites
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Score > 10
    AND p.Tags LIKE '%sql%'
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        AVG(COALESCE(v.BountyAmount, 0)) AS AvgBounty,
        STRING_AGG(b.Name, ', ') AS BadgeNames
    FROM Users u
    LEFT OUTER JOIN Badges b ON u.Id = b.UserId AND b.Class = 1
    LEFT OUTER JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId = 8
    GROUP BY u.Id, u.Reputation, u.DisplayName
    HAVING COUNT(DISTINCT b.Id) > 0 OR u.Reputation > 1000
),
AnswerMetrics AS (
    SELECT 
        p.ParentId AS QuestionId,
        p.OwnerUserId,
        SUM(p.Score) AS TotalAnswerScore,
        COUNT(*) AS AnswerCount,
        MAX(CASE WHEN p.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END) AS HasAccepted
    FROM Posts p
    INNER JOIN Posts q ON p.ParentId = q.Id
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId, p.OwnerUserId
),
Combined AS (
    SELECT 
        tq.QuestionId,
        tq.OwnerUserId AS QuestionOwner,
        us.Reputation,
        us.DisplayName,
        us.BadgeCount,
        us.AvgBounty,
        us.BadgeNames,
        tq.Score AS QuestionScore,
        tq.ViewCount,
        tq.Favorites,
        am.TotalAnswerScore,
        am.AnswerCount,
        am.HasAccepted,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = tq.QuestionId AND c.Score > 0) AS PositiveComments,
        COALESCE(NULLIF(tq.Tags, ''), 'No Tags') AS ProcessedTags,
        RANK() OVER (ORDER BY tq.Score + COALESCE(am.TotalAnswerScore, 0) DESC) AS OverallRank
    FROM TopQuestions tq
    INNER JOIN UserStats us ON tq.OwnerUserId = us.UserId
    LEFT OUTER JOIN AnswerMetrics am ON tq.QuestionId = am.QuestionId AND tq.OwnerUserId = am.OwnerUserId
    WHERE tq.QuestionRank = 1
    UNION
    SELECT 
        pl.RelatedPostId AS QuestionId,
        p.OwnerUserId AS QuestionOwner,
        us.Reputation,
        us.DisplayName,
        us.BadgeCount,
        us.AvgBounty,
        us.BadgeNames,
        p.Score AS QuestionScore,
        p.ViewCount,
        COALESCE(p.FavoriteCount, 0) AS Favorites,
        NULL AS TotalAnswerScore,
        NULL AS AnswerCount,
        NULL AS HasAccepted,
        0 AS PositiveComments,
        COALESCE(NULLIF(p.Tags, ''), 'No Tags') AS ProcessedTags,
        RANK() OVER (ORDER BY p.Score DESC) AS OverallRank
    FROM PostLinks pl
    INNER JOIN Posts p ON pl.RelatedPostId = p.Id
    INNER JOIN UserStats us ON p.OwnerUserId = us.UserId
    WHERE pl.LinkTypeId = 3 AND p.PostTypeId = 1
)
SELECT 
    QuestionId,
    QuestionOwner,
    Reputation,
    DisplayName,
    BadgeCount,
    AvgBounty,
    BadgeNames,
    QuestionScore,
    ViewCount,
    Favorites,
    TotalAnswerScore,
    AnswerCount,
    HasAccepted,
    PositiveComments,
    ProcessedTags,
    OverallRank,
    CASE 
        WHEN Reputation > 10000 THEN 'High Rep'
        WHEN Reputation BETWEEN 1000 AND 10000 THEN 'Medium Rep'
        ELSE 'Low Rep'
    END AS RepCategory
FROM Combined
WHERE OverallRank <= 10
ORDER BY OverallRank;