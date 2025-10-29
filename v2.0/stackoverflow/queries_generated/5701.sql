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
    WHERE p.CreationDate >= TIMESTAMP '2023-01-01 00:00:00'
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
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesCast,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesCast,
        MAX(v.CreationDate) AS LastVoteDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY u.Id
),
TagPopularity AS (
    SELECT
        t.TagName,
        COUNT(*) AS TagCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.LastActivityDate) AS LastActive
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    ) t1
    JOIN Tags t ON t.TagName = t1.TagName
    GROUP BY t.TagName
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
        ROW_NUMBER() OVER (ORDER BY c.LastActivityDate DESC NULLS LAST) AS recnum
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
    c.TagName AS TrendingTag,
    t2.AvgPostScore AS AvgTagPostScore,
    t2.TagCount AS TagTotalUsage
FROM Correlation c
LEFT JOIN (
    SELECT t.TagName, AVG(p.Score) AS AvgPostScore, COUNT(*) AS TagCount
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(substr(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    ) t
    GROUP BY t.TagName
) t2 ON true
ORDER BY c.LastActivityDate DESC
LIMIT 200;