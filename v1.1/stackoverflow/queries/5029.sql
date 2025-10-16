WITH RecentActiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.LastAccessDate,
        ROW_NUMBER() OVER (ORDER BY u.LastAccessDate DESC) AS rn
    FROM Users u
    WHERE u.LastAccessDate > (SELECT MAX(CreationDate) FROM Posts) - INTERVAL '30 days'
),
UserBadgeAgg AS (
    SELECT 
        UserId, 
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
TopQuestions AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year')
      AND p.Score > 10
),
TopQuestionLinks AS (
    SELECT 
        tq.PostId,
        COUNT(DISTINCT pl.Id) AS OutboundLinks,
        SUM(CASE WHEN lt.Name = 'Duplicate' THEN 1 ELSE 0 END) AS DuplicateLinks
    FROM TopQuestions tq
    LEFT JOIN PostLinks pl ON tq.PostId = pl.PostId
    LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY tq.PostId
),
CorrelatedComments AS (
    SELECT 
        c.Id AS CommentId,
        c.PostId,
        c.UserId,
        c.Text,
        c.Score,
        CASE 
            WHEN c.UserId IS NULL THEN 'Anonymous'
            ELSE COALESCE(u.DisplayName, 'Unknown')
        END AS CommenterDisplayName,
        ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.Score DESC, c.CreationDate ASC) AS CommentRank
    FROM Comments c
    LEFT JOIN Users u ON c.UserId = u.Id
),
QuestionTagSplit AS (
    -- Use standard SQL: remove leading '<' and trailing '>' then split on '><'.
    -- Implement splitting using a recursive CTE for broader SQL compatibility.
    SELECT
        tq.PostId,
        tag AS TagName
    FROM TopQuestions tq
    CROSS JOIN LATERAL (
        WITH RECURSIVE parts(pos, rest) AS (
            SELECT
                1 AS pos,
                CASE
                    WHEN tq.Tags IS NULL THEN ''
                    WHEN LENGTH(tq.Tags) >= 2 THEN SUBSTRING(tq.Tags FROM 2 FOR (LENGTH(tq.Tags) - 2))
                    ELSE ''
                END AS rest
            UNION ALL
            SELECT
                pos + 1,
                CASE
                    WHEN POSITION('><' IN rest) > 0 THEN SUBSTRING(rest FROM POSITION('><' IN rest) + 2)
                    ELSE ''
                END
            FROM parts
            WHERE rest <> '' AND POSITION('><' IN rest) > 0
        ),
        extracted AS (
            SELECT
                CASE
                    WHEN POSITION('><' IN rest) > 0 THEN SUBSTRING(rest FROM 1 FOR POSITION('><' IN rest) - 1)
                    ELSE rest
                END AS tag,
                pos
            FROM parts
            WHERE rest <> ''
        )
        SELECT tag FROM extracted
    ) s(tag)
),
PopularTags AS (
    SELECT 
        qs.TagName,
        COUNT(DISTINCT qs.PostId) AS QuestionCount
    FROM QuestionTagSplit qs
    GROUP BY qs.TagName
    HAVING COUNT(DISTINCT qs.PostId) > 5
),
PopularTagList AS (
    SELECT DISTINCT TagName AS TagName FROM PopularTags
)
SELECT
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    COALESCE(uba.TotalBadges, 0) AS TotalBadges,
    COALESCE(uba.GoldBadges, 0) AS GoldBadges,
    COALESCE(uba.SilverBadges, 0) AS SilverBadges,
    COALESCE(uba.BronzeBadges, 0) AS BronzeBadges,
    tq.PostId,
    tq.Title AS QuestionTitle,
    tq.Score AS QuestionScore,
    tq.ViewCount,
    tpl.OutboundLinks,
    tpl.DuplicateLinks,
    pc.TagName AS PopularTagUsed,
    cc.CommentId AS TopCommentId,
    cc.CommenterDisplayName,
    cc.Text AS TopCommentText,
    CASE 
        WHEN tq.Score >= 100 THEN 'Superstar'
        WHEN tq.Score BETWEEN 50 AND 99 THEN 'Rockstar'
        WHEN tq.Score BETWEEN 20 AND 49 THEN 'Popular'
        ELSE 'Trending'
    END AS QuestionHitLevel,
    CASE 
        WHEN tq.ViewCount IS NULL OR tq.ViewCount = 0 THEN NULL
        ELSE ROUND(CAST(tq.Score AS numeric) / NULLIF(tq.ViewCount,0), 3)
    END AS ScoreViewRatio
FROM RecentActiveUsers ru
LEFT JOIN UserBadgeAgg uba ON ru.UserId = uba.UserId
LEFT JOIN TopQuestions tq ON tq.OwnerUserId = ru.UserId
LEFT JOIN TopQuestionLinks tpl ON tq.PostId = tpl.PostId
LEFT JOIN CorrelatedComments cc ON cc.PostId = tq.PostId AND cc.CommentRank = 1
LEFT JOIN (
    SELECT qs.PostId, ptl.TagName
    FROM QuestionTagSplit qs
    JOIN PopularTagList ptl ON qs.TagName = ptl.TagName
    GROUP BY qs.PostId, ptl.TagName
) pc ON pc.PostId = tq.PostId
WHERE ru.rn <= 50
GROUP BY
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.LastAccessDate,
    ru.rn,
    uba.TotalBadges,
    uba.GoldBadges,
    uba.SilverBadges,
    uba.BronzeBadges,
    tq.PostId,
    tq.OwnerUserId,
    tq.Score,
    tq.ViewCount,
    tq.Title,
    tq.Tags,
    tpl.OutboundLinks,
    tpl.DuplicateLinks,
    pc.TagName,
    cc.CommentId,
    cc.PostId,
    cc.UserId,
    cc.Text,
    cc.Score,
    cc.CommenterDisplayName,
    cc.CommentRank
ORDER BY ru.Reputation DESC, tq.Score DESC, tq.ViewCount DESC;