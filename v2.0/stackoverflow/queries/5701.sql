-- {"query": "5701.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 876}
WITH
RecentTopPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.OwnerDisplayName,
        p.LastActivityDate,
        p.CommentCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.PostTypeId,
        ROW_NUMBER() OVER (
            PARTITION BY p.PostTypeId
            ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
        ) AS rn
    FROM Posts p
    WHERE p.CreationDate >= CAST('2023-01-01 00:00:00' AS TIMESTAMP)
      AND p.PostTypeId IN (1, 2) -- Questions and Answers
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.ProfileImageUrl,
        u.Location,
        u.AccountId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesCast,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesCast,
        MAX(v.CreationDate) AS LastVoteDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.ProfileImageUrl,
        u.Location,
        u.AccountId
),
TagPopularity AS (
    SELECT
        t1.TagName,
        COUNT(*) AS TagCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.LastActivityDate) AS LastActive
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    ) t1
    JOIN Tags t ON t.TagName = t1.TagName
    GROUP BY t1.TagName
),
Coalesced AS (
    SELECT
        rp.PostId,
        rp.Title,
        rp.Tags,
        rp.CreationDate,
        rp.Score,
        rp.ViewCount,
        rp.OwnerUserId,
        rp.OwnerDisplayName,
        rp.LastActivityDate,
        rp.CommentCount,
        rp.AnswerCount,
        rp.FavoriteCount,
        rp.PostTypeId,
        u.UserId AS PosterUserId,
        u.DisplayName AS PosterDisplayName,
        u.Reputation AS PosterReputation,
        u.LastAccessDate,
        u.AccountId,
        u.LastVoteDate
    FROM RecentTopPosts rp
    LEFT JOIN UserActivity u ON u.UserId = rp.OwnerUserId
),
Correlation AS (
    SELECT
        c.*,
        ROW_NUMBER() OVER (ORDER BY c.LastActivityDate DESC) AS recnum
    FROM Coalesced c
)
SELECT
    c.PostId,
    c.Title,
    c.Tags,
    c.CreationDate,
    c.Score,
    c.ViewCount,
    c.OwnerDisplayName AS Owner,
    c.LastActivityDate,
    c.CommentCount,
    c.AnswerCount,
    c.FavoriteCount,
    CASE
        WHEN c.PostTypeId = 1 THEN 'Question'
        WHEN c.PostTypeId = 2 THEN 'Answer'
        ELSE 'Other'
    END AS PostType,
    c.PosterDisplayName AS Poster,
    c.PosterReputation,
    c.LastAccessDate,
    tp.TagName AS TrendingTag,
    tp.AvgPostScore AS AvgTagPostScore,
    tp.TagCount AS TagTotalUsage
FROM Correlation c
LEFT JOIN (
    SELECT t1.TagName, AVG(p.Score) AS AvgPostScore, COUNT(*) AS TagCount
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    ) t1
    GROUP BY t1.TagName
) tp ON tp.TagName = ( -- choose a tag from the post's tag list; pick the first tag in the Tags string
    CASE
        WHEN c.Tags IS NULL THEN NULL
        ELSE
            -- extract first tag between angle brackets: <tag1><tag2>...
            SUBSTRING(c.Tags FROM 2 FOR (POSITION('>' IN c.Tags || '>') - 2))
    END
)
ORDER BY c.LastActivityDate DESC
LIMIT 200;