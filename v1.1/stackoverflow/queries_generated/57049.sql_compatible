WITH TopUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes
    FROM
        Users u
    JOIN
        Posts p ON u.Id = p.OwnerUserId
    JOIN
        Votes v ON p.Id = v.PostId
    WHERE
        p.PostTypeId IN (1, 2)
    GROUP BY
        u.Id, u.DisplayName
    ORDER BY
        TotalScore DESC
    LIMIT 100
), RecentPostsWithTags AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Tags,
        p.ViewCount,
        p.AnswerCount,
        p.CreationDate,
        u.Id AS OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        t.TagName,
        t.ExcerptPostId
    FROM
        Posts p
    LEFT JOIN Tags t ON p.Id = t.ExcerptPostId
    JOIN
        Users u ON p.OwnerUserId = u.Id
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days')
    ORDER BY
        p.ViewCount DESC
    LIMIT 1000
), HighTrafficTags AS (
    SELECT
        rp.Tags,
        STRING_AGG(DISTINCT t.TagName, ' ' ORDER BY t.TagName) AS TagNames,
        AVG(rp.ViewCount) AS AverageViews
    FROM
        RecentPostsWithTags rp
    LEFT JOIN Tags t
        ON t.TagName = ANY (STRING_TO_ARRAY(rp.Tags, '><'))
    GROUP BY
        rp.Tags
    ORDER BY
        AverageViews DESC
    LIMIT 20
), TagActivity AS (
    SELECT
        t.TagName,
        SUM(p.ViewCount) AS ViewTotal,
        COUNT(DISTINCT c.UserId) AS UniqueCommenters,
        AVG(p.ViewCount) AS AvgViews,
        SUM(p.AnswerCount) AS AnswerTotal,
        MAX(p.Id) AS LatestPostId,
        MAX(p.CreationDate) AS LatestPostDate
    FROM
        RecentPostsWithTags rp
    JOIN Tags t ON t.TagName = ANY (STRING_TO_ARRAY(rp.Tags, '><'))
    JOIN Posts p ON p.Id = rp.PostId
    LEFT JOIN Comments c ON c.PostId = rp.PostId
    LEFT JOIN Votes v ON v.PostId = c.PostId
    GROUP BY
        t.TagName
    ORDER BY
        AvgViews DESC,
        UniqueCommenters DESC,
        LatestPostDate DESC,
        ViewTotal DESC,
        AnswerTotal DESC
), TagRankings AS (
    SELECT
        t1.TagName,
        t1.AnswerTotal,
        t1.ViewTotal,
        t1.AvgViews,
        DENSE_RANK() OVER (ORDER BY t1.AvgViews DESC, t1.UniqueCommenters DESC, t1.LatestPostDate DESC) AS TagRank,
        DENSE_RANK() OVER (ORDER BY (t1.AvgViews * RANDOM() + t1.UniqueCommenters + EXTRACT(EPOCH FROM t1.LatestPostDate))) AS RandomTagPos
    FROM
        TagActivity t1
)
SELECT
    tu.UserId,
    tu.DisplayName,
    p.PostId AS Id,
    p.Title,
    p.Tags,
    p.ViewCount,
    p.AnswerCount,
    tu.TotalScore,
    tu.TotalUpVotes,
    tu.TotalDownVotes,
    t2.TagName,
    t2.TagRank,
    t2.RandomTagPos,
    t2.AnswerTotal,
    t2.ViewTotal,
    t2.AvgViews
FROM
    TopUsers tu
JOIN
    RecentPostsWithTags p ON tu.UserId = p.OwnerUserId
LEFT JOIN LATERAL (
    SELECT tr.*
    FROM TagRankings tr
    WHERE tr.TagName = ANY (STRING_TO_ARRAY(p.Tags, '><'))
    ORDER BY tr.TagRank, tr.RandomTagPos
    LIMIT 1
) t2 ON TRUE
WHERE
    (t2.TagRank IS NOT NULL AND t2.TagRank < 11)
    OR (t2.RandomTagPos IS NOT NULL AND t2.RandomTagPos < 11)
ORDER BY
    tu.TotalScore DESC,
    COALESCE(t2.TagRank, 9999),
    COALESCE(t2.RandomTagPos, 9999),
    p.ViewCount DESC;