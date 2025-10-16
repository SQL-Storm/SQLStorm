-- {"query": "5092.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1083} 
WITH RecentQuestions AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName AS OwnerName,
        p.Score,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 -- questions only
    AND p.CreationDate >= NOW() - INTERVAL '90 days'
),
MostActiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        SUM(COALESCE(p.Score,0) + COALESCE(a.Score,0)) AS TotalPostScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    WHERE u.CreationDate < NOW() - INTERVAL '180 days'
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) >= 3 AND COUNT(DISTINCT a.Id) >= 5
),
UserBadges AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        STRING_AGG(DISTINCT b.Name, ', ') AS BadgeList
    FROM Badges b
    GROUP BY b.UserId
),
FrequentTags AS (
    SELECT 
        t.TagName, 
        t.Count,
        RANK() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0
),
LinkedQuestionPairs AS (
    SELECT
        pl.PostId AS QuestionId,
        pl.RelatedPostId AS LinkedId,
        lt.Name AS LinkType,
        pl.CreationDate
    FROM PostLinks pl
    INNER JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE pl.PostId < pl.RelatedPostId -- avoid double counting links
)
SELECT
    rq.QuestionId,
    rq.Title,
    rq.CreationDate,
    rq.OwnerUserId,
    u.DisplayName AS OwnerName,
    ma.QuestionCount,
    ma.AnswerCount,
    ma.TotalPostScore,
    COALESCE(ub.GoldBadges,0) AS GoldBadges,
    COALESCE(ub.SilverBadges,0) AS SilverBadges,
    COALESCE(ub.BronzeBadges,0) AS BronzeBadges,
    COALESCE(ub.BadgeList, '') AS BadgeList,
    pl.LinkedCount,
    ft.TagName AS MostFrequentTag,
    ft.TagRank,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rq.QuestionId AND c.Score > 0) AS PositiveComments,
    (SELECT AVG(CAST(ph.CreationDate AS DATE) - CAST(rq.CreationDate AS DATE))
        FROM PostHistory ph
        WHERE ph.PostId = rq.QuestionId
        AND ph.PostHistoryTypeId IN (4,5,6) -- edits to title/body/tags
    ) AS AvgDaysToEdit,
    CASE 
        WHEN rq.Score >= 10 THEN 'Hot'
        WHEN rq.Score BETWEEN 3 AND 9 THEN 'Warm'
        ELSE 'Cold'
    END AS ScoreCategory,
    CASE
        WHEN rq.Tags ILIKE '%<sql>%'
          OR rq.Tags ILIKE '%<performance>%'
          OR rq.Tags ILIKE '%<benchmark>%'
          THEN TRUE
        ELSE FALSE
    END AS IsPerformanceRelated
FROM RecentQuestions rq
JOIN MostActiveUsers ma ON rq.OwnerUserId = ma.UserId
LEFT JOIN UserBadges ub ON rq.OwnerUserId = ub.UserId
LEFT JOIN (
    SELECT 
        pl.QuestionId,
        COUNT(*) AS LinkedCount
    FROM LinkedQuestionPairs pl
    GROUP BY pl.QuestionId
) pl ON rq.QuestionId = pl.QuestionId
LEFT JOIN LATERAL (
    SELECT 
        tag.TagName,
        tag.TagRank
    FROM FrequentTags tag
    WHERE EXISTS (
        SELECT 1
        FROM unnest(string_to_array(substring(rq.Tags, 2, length(rq.Tags)-2), '><')) AS qtag
        WHERE tag.TagName ILIKE qtag
    )
    ORDER BY tag.TagRank
    LIMIT 1
) ft ON TRUE
WHERE rq.rn = 1
AND (pl.LinkedCount IS NULL OR pl.LinkedCount >= 2)
ORDER BY
    ScoreCategory DESC,
    pl.LinkedCount DESC NULLS LAST,
    ma.TotalPostScore DESC,
    rq.CreationDate DESC
LIMIT 50;