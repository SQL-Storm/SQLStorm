WITH ActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate,
        COUNT(p.Id) AS PostCount,
        COUNT(c.Id) AS CommentCount,
        COUNT(v.Id) AS VoteCount
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    WHERE
        u.LastAccessDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY)
    GROUP BY
        u.Id, u.Reputation, u.CreationDate
),
TopTags AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS QuestionCount,
        AVG(p.Score) AS AvgScore,
        SUM(p.ViewCount) AS TotalViews
    FROM
        Tags t
    JOIN
        Posts p ON t.TagName = ANY(
            -- convert the tags string like '<tag1><tag2>' into an array of tag names
            -- use regexp to extract tag names in a dialect-agnostic way where possible
            regexp_split_to_array(
                regexp_replace(p.Tags, '^<|>$', '', 'g'),
                '><'
            )
        )
    WHERE
        p.PostTypeId = 1
    GROUP BY
        t.TagName
    ORDER BY
        QuestionCount DESC
    LIMIT 10
),
UserActivity AS (
    SELECT
        au.UserId,
        au.Reputation,
        au.CreationDate,
        au.PostCount,
        au.CommentCount,
        au.VoteCount,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(SUM(p.ViewCount), 0) AS TotalPostViews,
        COUNT(DISTINCT b.Id) AS BadgeCount
    FROM
        ActiveUsers au
    LEFT JOIN
        Posts p ON au.UserId = p.OwnerUserId
    LEFT JOIN
        Badges b ON au.UserId = b.UserId
    GROUP BY
        au.UserId, au.Reputation, au.CreationDate, au.PostCount, au.CommentCount, au.VoteCount
)
SELECT
    ua.UserId,
    ua.Reputation,
    ua.CreationDate,
    ua.PostCount,
    ua.CommentCount,
    ua.VoteCount,
    ua.TotalPostScore,
    ua.TotalPostViews,
    ua.BadgeCount,
    tt.TagName,
    tt.QuestionCount,
    tt.AvgScore,
    tt.TotalViews
FROM
    UserActivity ua
CROSS JOIN
    TopTags tt
ORDER BY
    ua.Reputation DESC,
    tt.QuestionCount DESC;