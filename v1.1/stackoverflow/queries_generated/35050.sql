-- {"query": "35050.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 589} 
WITH TopAnswerers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AvgScore
    FROM
        Users u
        JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE
        p.PostTypeId = 2
        AND p.CreationDate >= NOW() - INTERVAL '1 year'
    GROUP BY
        u.Id, u.DisplayName
    HAVING
        COUNT(DISTINCT p.Id) >= 50
),
AnswerBadges AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM
        Badges b
    GROUP BY
        b.UserId
),
AnswerCommentStats AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(c.Id) AS TotalComments,
        AVG(c.Score) AS AvgCommentScore
    FROM
        Posts p
        JOIN Comments c ON p.Id = c.PostId
    WHERE
        p.PostTypeId = 2
    GROUP BY
        p.OwnerUserId
),
TagDiversity AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))) AS TagCount
    FROM
        Posts p
    WHERE
        p.PostTypeId = 2
        AND p.Tags IS NOT NULL
    GROUP BY
        p.OwnerUserId
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
    TopAnswerers ta
    LEFT JOIN AnswerBadges ab ON ta.UserId = ab.UserId
    LEFT JOIN AnswerCommentStats acs ON ta.UserId = acs.UserId
    LEFT JOIN TagDiversity td ON ta.UserId = td.UserId
ORDER BY
    ta.TotalScore DESC,
    ta.AnswerCount DESC
LIMIT 25;