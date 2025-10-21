-- {"query": "57036.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 967} 

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
        u.LastAccessDate > NOW() - INTERVAL '1 month'
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
        Posts p ON t.TagName = ANY(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), ''><''))
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
        COUNT(c.Id) AS CommentCount
    FROM
        Posts p
    JOIN
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    WHERE
        p.CreationDate > NOW() - INTERVAL '1 year'
    GROUP BY
        p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.Title, u.DisplayName
    ORDER BY
        VoteCount DESC
    LIMIT 50
)

SELECT
    au.UserId,
    au.DisplayName AS ActiveUser,
    au.Reputation AS ActiveUserReputation,
    au.PostCount,
    au.CommentCount,
    au.VoteCount,
    pt.Name AS PopularTag,
    p.TagName,
    p.QuestionsWithTag,
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
	RecentHighVotePosts rhvp on au.UserId = rhvp.UserId or hu.UserId = rhvp.UserId
ORDER BY
    rhvp.PostVoteCount DESC,
    hu.Reputation DESC,
    au.Reputation DESC
LIMIT 100;
