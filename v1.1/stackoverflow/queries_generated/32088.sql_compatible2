WITH RECURSIVE RecursivePostLinks AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        1 AS LinkDepth,
        ARRAY[pl.Id] AS Path
    FROM
        PostLinks pl
    WHERE
        pl.LinkTypeId = 1

    UNION ALL

    SELECT
        rpl.PostId,
        pl.RelatedPostId,
        rpl.LinkDepth + 1 AS LinkDepth,
        (rpl.Path || ARRAY[pl.Id]) AS Path
    FROM
        RecursivePostLinks rpl
    JOIN
        PostLinks pl ON rpl.RelatedPostId = pl.PostId
    WHERE
        pl.LinkTypeId = 1
        AND NOT pl.Id = ANY(rpl.Path)
),

HighScoreQuestions AS (
    SELECT
        p.Id AS PostId,
        p.Score
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1
        AND p.Score > 100
)

SELECT
    u.DisplayName,
    u.Id AS UserId,
    COUNT(b.Id) AS TotalBadges,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
    COUNT(DISTINCT rp.PostId) AS RecursiveLinkCount,
    COUNT(DISTINCT hq.PostId) AS HighScoreQuestionCount
FROM
    Users u
LEFT JOIN
    Badges b ON u.Id = b.UserId
LEFT JOIN
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN
    RecursivePostLinks rp ON p.Id = rp.PostId
LEFT JOIN
    HighScoreQuestions hq ON p.Id = hq.PostId
GROUP BY
    u.Id,
    u.DisplayName
ORDER BY
    TotalBadges DESC,
    GoldBadges DESC,
    HighScoreQuestionCount DESC,
    RecursiveLinkCount DESC
LIMIT 50;