-- {"query": "27098.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 1307} 

WITH RecentActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COUNT(p.Id) AS PostCount,
        COUNT(c.Id) AS CommentCount,
        COUNT(v.Id) AS VoteCount,
        MAX(p.LastActivityDate) AS LastPostActivity,
        MAX(c.CreationDate) AS LastCommentDate,
        MAX(v.CreationDate) AS LastVoteDate
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    WHERE
        u.LastAccessDate >= NOW() - INTERVAL '30 days'
    GROUP BY
        u.Id, u.Reputation, u.DisplayName
),
HighActivityPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        COALESCE(p.Title, '') AS PostTitle,
        COALESCE(p.Tags, '') AS PostTags,
        COUNT(v.Id) AS VoteCount,
        COUNT(c.Id) AS CommentCount,
        COUNT(ph.Id) AS HistoryCount
    FROM
        Posts p
    LEFT JOIN
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        PostHistory ph ON p.Id = ph.PostId
    WHERE
        p.CreationDate >= NOW() - INTERVAL '60 days'
    GROUP BY
        p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount,
        p.AnswerCount, p.CommentCount, p.OwnerUserId, u.DisplayName, p.Title, p.Tags
),
TagMetrics AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        t.Count AS TagCount,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgPostScore,
        SUM(p.ViewCount) AS TotalViewCount
    FROM
        Tags t
    LEFT JOIN
        Posts p ON t.Id = ANY(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><'))
    WHERE
        t.Count > 1000
    GROUP BY
        t.Id, t.TagName, t.Count
)
SELECT
    ra.UserId,
    ra.DisplayName,
    ra.Reputation,
    ra.PostCount,
    ra.CommentCount,
    ra.VoteCount,
    ra.LastPostActivity,
    ra.LastCommentDate,
    ra.LastVoteDate,
    hp.PostId,
    pt.Name AS PostTypeName,
    hp.CreationDate,
    hp.Score,
    hp.ViewCount,
    hp.AnswerCount,
    hp.CommentCount,
    hp.OwnerDisplayName,
    hp.PostTitle,
    hp.PostTags,
    tm.TagId,
    tm.TagName,
    tm.TagCount,
    tm.PostCount AS TagPostCount,
    tm.AvgPostScore,
    tm.TotalViewCount,
    LAG(ra.Reputation, 1) OVER (PARTITION BY ra.UserId ORDER BY ra.Reputation DESC) AS PreviousReputation,
    LEAD(ra.Reputation, 1) OVER (PARTITION BY ra.UserId ORDER BY ra.Reputation DESC) AS NextReputation,
    RANK() OVER (PARTITION BY tm.TagId ORDER BY tm.PostCount DESC) AS TagRank,
    DENSE_RANK() OVER (PARTITION BY ra.UserId ORDER BY ra.PostCount DESC) AS UserPostRank,
    NTILE(10) OVER (PARTITION BY ra.UserId ORDER BY ra.CommentCount DESC) AS UserCommentDecile
FROM
    RecentActiveUsers ra
JOIN
    HighActivityPosts hp ON ra.UserId = hp.OwnerUserId
LEFT JOIN
    PostTypes pt ON hp.PostTypeId = pt.Id
LEFT JOIN
    TagMetrics tm ON hp.PostId = ANY(string_to_array(SUBSTRING(hp.PostTags FROM 2 FOR LENGTH(hp.PostTags) - 2), '><')) OR tm.TagName IS NULL
WHERE
    (ra.PostCount > 10 OR ra.CommentCount > 20)
    AND (hp.Score > 5 OR hp.ViewCount > 100)
    AND (tm.PostCount > 50 OR tm.AvgPostScore > 2)
ORDER BY
    ra.Reputation DESC, hp.Score DESC, tm.PostCount DESC;
