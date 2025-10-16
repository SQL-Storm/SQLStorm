-- {"query": "12010.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 820} 

WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS PostRank,
        COUNT(v.Id) OVER (PARTITION BY p.Id) AS TotalVotes,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS DownVotes
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
),
TopPostUsers AS (
    SELECT 
        OwnerUserId,
        COUNT(Id) AS PostCount,
        SUM(Score) AS TotalScore,
        STRING_AGG(DISTINCT Tags, ' | ') WITHIN GROUP (ORDER BY Tags) AS TagList
    FROM 
        RankedPosts
    WHERE 
        PostRank <= 5
    GROUP BY 
        OwnerUserId
),
UserActivity AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Comments c ON u.Id = c.UserId
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location
),
PostTagStats AS (
    SELECT 
        t.TagName,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgScore,
        MAX(p.CreationDate) AS LatestPostDate
    FROM 
        Tags t
    JOIN 
        Posts p ON t.WikiPostId = p.Id OR t.ExcerptPostId = p.Id
    GROUP BY 
        t.TagName
)
SELECT 
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    ua.PostCount AS UserPostCount,
    ua.CommentCount AS UserCommentCount,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    ts.TagName,
    ts.PostCount AS TagPostCount,
    ts.AvgScore,
    ts.LatestPostDate
FROM 
    UserActivity u
JOIN 
    TopPostUsers tpu ON u.Id = tpu.OwnerUserId
JOIN 
    PostTagStats ts ON tpu.TagList LIKE '%' || ts.TagName || '%'
WHERE 
    u.Reputation > 1000
ORDER BY 
    u.Reputation DESC, ts.PostCount DESC;
