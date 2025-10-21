-- {"query": "54017.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1643} 

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
    LATERAL regexp_split_to_table(
        regexp_replace(ups.Tags, '^<|>$', '', 'g'), '><'
    ) AS tag
),
tag_stats AS (
    SELECT
        Tag,
        COUNT(PostId)              AS PostCount,
        SUM(Score)                 AS TotalScore,
        AVG(Score)                 AS AvgScore,
        STRING_AGG(DISTINCT UserId::text, ',') AS Users
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
ORDER BY uts.UserId, uts.Tag
LIMIT 1000;
