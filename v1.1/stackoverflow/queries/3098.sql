-- {"query": "3098.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 903} 
WITH AnswerScoreStats AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score AS TotalScore,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS RankByScore
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Questions only
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS VoteImpact,
        MAX(p.LastActivityDate) AS LastActive
    FROM Users u
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName
),
TagUsage AS (
    SELECT
        t.TagName,
        COUNT(*) AS UsageCount,
        ARRAY_AGG(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionIds
    FROM Tags t
    LEFT JOIN Posts p ON t.ExcerptPostId = p.Id OR t.WikiPostId = p.Id
    GROUP BY t.TagName
),
RecentEdits AS (
    SELECT
        ph.PostId,
        COUNT(*) AS EditCount,
        STRING_AGG(ph.UserDisplayName, ', ') AS Editors
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,10,11,12,13,14,15,16)
    GROUP BY ph.PostId
),
PostLinkCounts AS (
    SELECT
        p.Id AS PostId,
        COUNT(pl.RelatedPostId) AS LinkCount,
        COUNT(DISTINCT pl.LinkTypeId) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateLinks,
        COUNT(DISTINCT pl.LinkTypeId) FILTER (WHERE pl.LinkTypeId = 1) AS LinkedPosts
    FROM Posts p
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    GROUP BY p.Id
),
ActiveUserReputation AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        CASE
            WHEN u.Reputation >= 2000 THEN 'High'
            WHEN u.Reputation BETWEEN 1000 AND 1999 THEN 'Moderate'
            ELSE 'Low'
        END AS ReputationTier
    FROM Users u
),
ComplexPredicate AS (
    SELECT
        p.Id,
        p.Title,
        p.ViewCount,
        p.Body,
        COALESCE(NULLIF(p.Title, ''), 'Untitled') AS SafeTitle,
        (p.Score * 1.0) / NULLIF(p.ViewCount, 0) AS ScoreDensity,
        CASE
            WHEN p.Tags IS NOT NULL AND p.Tags LIKE '%<sql>%' THEN TRUE
            ELSE FALSE
        END AS ContainsSqlTag
    FROM Posts p
    WHERE p.PostTypeId = 1
)
SELECT
    a.UserId,
    a.DisplayName,
    a.CommentCount,
    a.VoteImpact,
    a.LastActive,
    t.TagName,
    t.UsageCount,
    ARRAY_LENGTH(t.QuestionIds, 1) AS QuestionCountForTag,
    e.EditCount,
    e.Editors,
    l.LinkCount,
    l.DuplicateLinks,
    l.LinkedPosts,
    r.Reputation,
    r.ReputationTier,
    c.Id AS PostId,
    c.Title,
    c.ViewCount,
    c.Body,
    c.SafeTitle,
    c.ScoreDensity,
    c.ContainsSqlTag
FROM UserActivity a
LEFT JOIN TagUsage t ON TRUE
LEFT JOIN RecentEdits e ON a.UserId = e.PostId
LEFT JOIN PostLinkCounts l ON l.PostId = a.UserId
LEFT JOIN ActiveUserReputation r ON a.UserId = r.UserId
LEFT JOIN ComplexPredicate c ON c.Id = a.UserId
WHERE
    a.CommentCount > 10
    AND a.VoteImpact >= 5
    AND r.Reputation >= 1000
    AND c.ScoreDensity > 0.05
    AND c.ContainsSqlTag = TRUE
ORDER BY a.LastActive DESC
LIMIT 100;