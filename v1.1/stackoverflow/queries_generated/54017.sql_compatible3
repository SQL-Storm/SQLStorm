WITH user_post_scores AS (
    SELECT
        p.OwnerUserId AS UserId,
        p.Id           AS PostId,
        p.Score,
        p.Tags
    FROM Posts p
    WHERE p.PostTypeId = 1
),
tags_extracted AS (
    SELECT
        ups.UserId,
        ups.PostId,
        ups.Score,
        UPPER(tag) AS Tag
    FROM user_post_scores ups,
    LATERAL (
        SELECT value AS tag
        FROM UNNEST(
            REGEXP_SPLIT_TO_ARRAY(REGEXP_REPLACE(ups.Tags, '^<|>$', ''), '><')
        ) AS t(value)
    ) s
),
tag_stats AS (
    SELECT
        Tag,
        COUNT(PostId)              AS PostCount,
        SUM(Score)                 AS TotalScore,
        AVG(Score)                 AS AvgScore,
        STRING_AGG(DISTINCT CAST(UserId AS VARCHAR), ',') AS Users
    FROM tags_extracted
    GROUP BY Tag
),
user_tag_summary AS (
    SELECT
        te.UserId,
        te.Tag,
        COUNT(te.PostId)            AS UserPostCount,
        SUM(te.Score)               AS UserTotalScore,
        AVG(te.Score)               AS UserAvgScore
    FROM tags_extracted te
    GROUP BY te.UserId, te.Tag
)
SELECT
    uts.UserId,
    uts.Tag,
    uts.UserPostCount,
    uts.UserTotalScore,
    uts.UserAvgScore,
    ts.TotalScore,
    ts.PostCount,
    ts.AvgScore,
    ts.Users AS RelatedUsers
FROM user_tag_summary uts
JOIN tag_stats ts ON ts.Tag = uts.Tag
GROUP BY
    uts.UserId,
    uts.Tag,
    uts.UserPostCount,
    uts.UserTotalScore,
    uts.UserAvgScore,
    ts.TotalScore,
    ts.PostCount,
    ts.AvgScore,
    ts.Users
ORDER BY uts.UserId, uts.Tag
LIMIT 1000;