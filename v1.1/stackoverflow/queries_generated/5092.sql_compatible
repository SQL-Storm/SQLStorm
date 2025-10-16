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
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days'
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
    WHERE u.CreationDate < CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days'
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) >= 3 AND COUNT(DISTINCT a.Id) >= 5
),
UserBadges AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        STRING_AGG(DISTINCT b.Name, ', ') AS BadgeList
    FROM Badges b
    GROUP BY b.UserId
),
FrequentTags AS (
    SELECT 
        t.TagName, 
        t.Count,
        RANK() OVER (ORDER BY t.Count DESC) AS TagRank,
        t.IsModeratorOnly,
        t.IsRequired
    FROM Tags t
    WHERE t.IsModeratorOnly = FALSE AND t.IsRequired = FALSE
),
LinkedQuestionPairs AS (
    SELECT
        pl.PostId AS QuestionId,
        pl.RelatedPostId AS LinkedId,
        lt.Name AS LinkType,
        pl.CreationDate
    FROM PostLinks pl
    INNER JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE pl.PostId < pl.RelatedPostId
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
          AND ph.PostHistoryTypeId IN (4,5,6)
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
    END AS IsPerformanceRelated,
    rq.rn
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
        FROM unnest(string_to_array(substring(rq.Tags, 2, length(rq.Tags)-2), '><')) AS qtag(qname)
        WHERE tag.TagName ILIKE qtag.qname
    )
    ORDER BY tag.TagRank
    LIMIT 1
) ft ON TRUE
LEFT JOIN Users u ON rq.OwnerUserId = u.Id
WHERE rq.rn = 1
  AND (pl.LinkedCount IS NULL OR pl.LinkedCount >= 2)
ORDER BY
    ScoreCategory DESC,
    pl.LinkedCount DESC,
    ma.TotalPostScore DESC,
    rq.CreationDate DESC
LIMIT 50;