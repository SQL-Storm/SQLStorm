-- {"query": "34056.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 944} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        1 AS Level,
        CAST(t.TagName AS VARCHAR(255)) AS FullPath
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT
        t.Id,
        t.TagName,
        rh.Level + 1,
        CAST(rh.FullPath || ' > ' || t.TagName AS VARCHAR(255))
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    JOIN RecursiveTagHierarchy rh ON rh.TagName = (SELECT unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) LIMIT 1)
    WHERE rh.Level < 3
),

UserBadgeScores AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(CASE b.Class WHEN 1 THEN 10 WHEN 2 THEN 5 WHEN 3 THEN 1 ELSE 0 END) AS BadgeScore,
        EXTRACT(YEAR FROM u.CreationDate) AS JoinYear
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, JoinYear
),

TopPostsAndActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1, 2)) AS AvgPostScore,
        COUNT(DISTINCT ph.Id) AS EditCount,
        MAX(p.LastActivityDate) AS LastActivity
    FROM Posts p
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6)
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY p.OwnerUserId
),

PostLinkAnalysis AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName,
        COUNT(*) OVER (PARTITION BY pl.PostId) AS OutboundLinkCount,
        COUNT(*) OVER (PARTITION BY pl.RelatedPostId) AS InboundLinkCount
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
),

FinalAggregated AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        ub.BadgeCount,
        ub.BadgeScore,
        ub.JoinYear,
        ta.QuestionCount,
        ta.AnswerCount,
        ta.AvgPostScore,
        ta.EditCount,
        ta.LastActivity,
        COALESCE(pl_stats.OutboundLinks, 0) AS TotalOutboundLinks,
        COALESCE(pl_stats.InboundLinks, 0) AS TotalInboundLinks
    FROM Users u
    LEFT JOIN UserBadgeScores ub ON ub.UserId = u.Id
    LEFT JOIN TopPostsAndActivity ta ON ta.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT
            p.OwnerUserId,
            COUNT(pl.Id) FILTER (WHERE lt.Name = 'Linked') AS OutboundLinks,
            COUNT(pl.Id) FILTER (WHERE lt.Name = 'Duplicate') AS InboundLinks
        FROM Posts p
        LEFT JOIN PostLinks pl ON pl.PostId = p.Id
        LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
        GROUP BY p.OwnerUserId
    ) pl_stats ON pl_stats.OwnerUserId = u.Id
    WHERE u.Reputation > 1000
)

SELECT
    fa.UserId,
    fa.DisplayName,
    fa.Reputation,
    fa.BadgeCount,
    fa.BadgeScore,
    fa.JoinYear,
    fa.QuestionCount,
    fa.AnswerCount,
    ROUND(fa.AvgPostScore::numeric, 2) AS AvgPostScore,
    fa.EditCount,
    fa.LastActivity,
    fa.TotalOutboundLinks,
    fa.TotalInboundLinks,
    rh.FullPath AS SampleTagHierarchy
FROM FinalAggregated fa
LEFT JOIN RecursiveTagHierarchy rh ON rh.Level = 1
ORDER BY fa.Reputation DESC, fa.BadgeScore DESC
LIMIT 50;
