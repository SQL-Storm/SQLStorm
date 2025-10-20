WITH ActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        COUNT(p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COUNT(DISTINCT b.Id) AS BadgeCount
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    WHERE
        u.LastAccessDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30' DAY)
    GROUP BY
        u.Id, u.Reputation
    HAVING
        COUNT(p.Id) > 0 OR COUNT(c.Id) > 0 OR COUNT(v.Id) > 0 OR COUNT(b.Id) > 0
),
HighlyVotedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        COUNT(v.Id) AS VoteCount,
        COUNT(c.Id) AS CommentCount,
        COUNT(DISTINCT l.RelatedPostId) AS RelatedPostCount,
        p.Tags
    FROM
        Posts p
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        PostLinks l ON p.Id = l.PostId
    WHERE
        p.PostTypeId = 1
        AND p.Score > 10
        AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1' YEAR)
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Title, p.Tags
    HAVING
        COUNT(v.Id) > 5 AND COUNT(c.Id) > 2
),
TopTags AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        t.Count,
        COUNT(p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        SUM(p.ViewCount) AS TotalViews
    FROM
        Tags t
    LEFT JOIN
        Posts p ON (
            EXISTS (
                SELECT 1
                FROM (
                    SELECT TRIM(value) AS tag
                    FROM (
                        SELECT UNNEST(string_to_array(p.Tags, '><')) AS value
                    ) AS exploded
                ) AS taglist
                WHERE taglist.tag = t.TagName
            )
        )
    WHERE
        t.Count > 1000
    GROUP BY
        t.Id, t.TagName, t.Count
    HAVING
        COUNT(p.Id) > 500 AND SUM(p.Score) > 1000
)
SELECT
    au.UserId,
    au.Reputation,
    au.PostCount,
    au.CommentCount,
    au.VoteCount,
    au.BadgeCount,
    hvp.PostId,
    hvp.PostTypeId,
    hvp.OwnerUserId,
    hvp.CreationDate,
    hvp.Score,
    hvp.ViewCount,
    hvp.Title,
    hvp.VoteCount AS HighlyVotedPostVoteCount,
    hvp.CommentCount AS HighlyVotedPostCommentCount,
    hvp.RelatedPostCount,
    tt.TagId,
    tt.TagName,
    tt.Count AS TagCount,
    tt.PostCount AS TagPostCount,
    tt.TotalScore,
    tt.TotalViews
FROM
    ActiveUsers au
JOIN
    HighlyVotedPosts hvp ON au.UserId = hvp.OwnerUserId
JOIN
    TopTags tt ON EXISTS (
        SELECT 1
        FROM (
            SELECT TRIM(value) AS tag
            FROM (
                SELECT UNNEST(string_to_array(hvp.Tags, '><')) AS value
            ) AS exploded
        ) AS taglist
        WHERE taglist.tag = tt.TagName
    )
ORDER BY
    au.Reputation DESC, hvp.Score DESC, tt.TotalScore DESC
LIMIT 100;