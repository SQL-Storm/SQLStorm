WITH TopAnswerers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgScore
    FROM
        Users AS u
        JOIN Posts AS p ON u.Id = p.OwnerUserId
    WHERE
        p.PostTypeId = 2
        AND p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year')
    GROUP BY
        u.Id, u.DisplayName
    HAVING
        COUNT(DISTINCT p.Id) >= 50
),
AnswerBadges AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM
        Badges AS b
    GROUP BY
        b.UserId
),
AnswerCommentStats AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(c.Id) AS TotalComments,
        AVG(c.Score) AS AvgCommentScore
    FROM
        Posts AS p
        JOIN Comments AS c ON p.Id = c.PostId
    WHERE
        p.PostTypeId = 2
    GROUP BY
        p.OwnerUserId
),
TagDiversity AS (
    SELECT
        t2.UserId,
        COUNT(DISTINCT t2.tag) AS TagCount
    FROM (
        SELECT
            p.OwnerUserId AS UserId,
            TRIM(value) AS tag
        FROM
            Posts AS p
            CROSS JOIN LATERAL (
                SELECT CAST(x AS VARCHAR) AS value
                FROM UNNEST(string_to_array(substring(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags) - 2), '><')) AS x
            ) AS t
    ) AS t2
    GROUP BY
        t2.UserId
)
SELECT
    ta.UserId,
    ta.DisplayName,
    ta.AnswerCount,
    ta.TotalScore,
    ta.AvgScore,
    COALESCE(ab.GoldBadges, 0) AS GoldBadges,
    COALESCE(ab.SilverBadges, 0) AS SilverBadges,
    COALESCE(ab.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(acs.TotalComments, 0) AS TotalComments,
    COALESCE(acs.AvgCommentScore, 0) AS AvgCommentScore,
    COALESCE(td.TagCount, 0) AS UniqueTagsAnsweredOn
FROM
    TopAnswerers AS ta
    LEFT JOIN AnswerBadges AS ab ON ta.UserId = ab.UserId
    LEFT JOIN AnswerCommentStats AS acs ON ta.UserId = acs.UserId
    LEFT JOIN TagDiversity AS td ON ta.UserId = td.UserId
ORDER BY
    ta.TotalScore DESC,
    ta.AnswerCount DESC
LIMIT 25;