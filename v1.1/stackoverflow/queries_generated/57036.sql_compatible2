WITH ActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
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
        u.LastAccessDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 month'
    GROUP BY
        u.Id, u.Reputation, u.DisplayName
),

PopularTags AS (
    SELECT
        t.TagName,
        t.Count,
        COUNT(p.Id) AS QuestionsWithTag
    FROM
        Tags t
    JOIN
        Posts p ON EXISTS (
            SELECT 1
            FROM unnest(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><')) AS tag
            WHERE tag = t.TagName
        )
    WHERE
        p.PostTypeId = 1
    GROUP BY
        t.TagName, t.Count
    ORDER BY
        QuestionsWithTag DESC
    LIMIT 10
 ),

 HighReputationUsers AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS Rank
    FROM
        Users u
    WHERE
        u.Reputation > 10000
    ORDER BY
        u.Reputation DESC
    LIMIT 20
),
RecentHighVotePosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        u.DisplayName AS Author,
        COUNT(v.Id) AS VoteCount,
        COUNT(c.Id) AS CommentCount,
        p.OwnerUserId
    FROM
        Posts p
    JOIN
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    WHERE
        p.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
    GROUP BY
        p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.Title, u.DisplayName, p.OwnerUserId
    ORDER BY
        COUNT(v.Id) DESC
    LIMIT 50
)

SELECT
    au.UserId,
    au.DisplayName AS ActiveUser,
    au.Reputation AS ActiveUserReputation,
    au.PostCount,
    au.CommentCount,
    au.VoteCount,
    pt.TagName AS PopularTag,
    pt.TagName AS TagName,
    pt.QuestionsWithTag,
    hu.DisplayName AS HighReputationUser,
    hu.Reputation AS HighReputation,
    hu.Rank,
    rhvp.PostId,
    rhvp.PostTypeId,
    rhvp.Title AS PostTitle,
    rhvp.Author,
    rhvp.Score,
    rhvp.ViewCount,
    rhvp.VoteCount AS PostVoteCount,
    rhvp.CommentCount AS PostCommentCount
FROM
    ActiveUsers au
CROSS JOIN
    PopularTags pt
CROSS JOIN
    HighReputationUsers hu
JOIN
    RecentHighVotePosts rhvp
    ON (au.UserId = rhvp.OwnerUserId OR hu.UserId = rhvp.OwnerUserId)
GROUP BY
    au.UserId,
    au.DisplayName,
    au.Reputation,
    au.PostCount,
    au.CommentCount,
    au.VoteCount,
    pt.TagName,
    pt.Count,
    pt.QuestionsWithTag,
    hu.UserId,
    hu.DisplayName,
    hu.Reputation,
    hu.Rank,
    rhvp.PostId,
    rhvp.PostTypeId,
    rhvp.CreationDate,
    rhvp.Score,
    rhvp.ViewCount,
    rhvp.Title,
    rhvp.Author,
    rhvp.VoteCount,
    rhvp.CommentCount,
    rhvp.OwnerUserId
ORDER BY
    PostVoteCount DESC,
    hu.Reputation DESC,
    au.Reputation DESC
LIMIT 100;