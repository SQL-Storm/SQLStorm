WITH ActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        COUNT(p.Id) AS PostCount,
        COUNT(DISTINCT p.Id) AS UniquePostCount,
        COUNT(c.Id) AS CommentCount,
        COUNT(DISTINCT c.Id) AS UniqueCommentCount,
        COUNT(v.Id) AS VoteCount,
        COUNT(DISTINCT v.Id) AS UniqueVoteCount
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    WHERE
        u.LastAccessDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
    GROUP BY
        u.Id, u.Reputation
),
TopTags AS (
    SELECT
        t.TagName,
        t.Count,
        COUNT(p.Id) AS PostsWithTag,
        AVG(p.Score) AS AverageScore,
        SUM(p.ViewCount) AS TotalViews
    FROM
        Tags t
    LEFT JOIN
        Posts p ON p.Tags LIKE ('%' || '<' || t.TagName || '>' || '%')
    GROUP BY
        t.Id, t.TagName, t.Count
    ORDER BY
        PostsWithTag DESC
    LIMIT 10
),
HighActivityPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        COUNT(v.Id) AS VoteCount,
        COUNT(c.Id) AS CommentCount,
        COUNT(ph.Id) AS PostHistoryCount,
        COUNT(DISTINCT ph.UserId) AS UniqueEditors
    FROM
        Posts p
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        PostHistory ph ON p.Id = ph.PostId
    WHERE
        p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
    GROUP BY
        p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId
    HAVING
        COUNT(v.Id) > 10 OR COUNT(c.Id) > 10 OR COUNT(ph.Id) > 5
    ORDER BY
        VoteCount DESC, CommentCount DESC, PostHistoryCount DESC
    LIMIT 20
)
SELECT
    au.UserId,
    au.Reputation,
    au.PostCount,
    au.UniquePostCount,
    au.CommentCount,
    au.UniqueCommentCount,
    au.VoteCount,
    au.UniqueVoteCount,
    tt.TagName,
    tt.Count AS TagCount,
    tt.PostsWithTag,
    tt.AverageScore,
    tt.TotalViews,
    hap.PostId,
    hap.PostTypeId,
    hap.CreationDate AS PostCreationDate,
    hap.Score AS PostScore,
    hap.ViewCount AS PostViewCount,
    hap.OwnerUserId AS PostOwnerUserId,
    hap.VoteCount AS PostVoteCount,
    hap.CommentCount AS PostCommentCount,
    hap.PostHistoryCount,
    hap.UniqueEditors
FROM
    ActiveUsers au
CROSS JOIN
    TopTags tt
LEFT JOIN
    HighActivityPosts hap ON au.UserId = hap.OwnerUserId
ORDER BY
    au.Reputation DESC,
    tt.PostsWithTag DESC,
    hap.Score DESC,
    hap.PostId,
    hap.PostTypeId,
    hap.CreationDate,
    hap.ViewCount,
    hap.OwnerUserId,
    hap.VoteCount,
    hap.CommentCount,
    hap.PostHistoryCount,
    hap.UniqueEditors;