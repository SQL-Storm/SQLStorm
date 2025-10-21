-- {"query": "12080.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 885} 

WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS UserRank,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) OVER (PARTITION BY p.Id) AS UpVotes,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) OVER (PARTITION BY p.Id) AS DownVotes,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCount,
        MAX(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6)) OVER (PARTITION BY p.Id) AS LastEditDate
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
),
TopPosters AS (
    SELECT 
        OwnerUserId,
        COUNT(Id) AS PostCount,
        SUM(Score) AS TotalScore
    FROM 
        RankedPosts
    WHERE 
        UserRank = 1
    GROUP BY 
        OwnerUserId
    HAVING 
        COUNT(Id) > 1
),
TagStats AS (
    SELECT 
        t.TagName,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgScore,
        MAX(p.CreationDate) AS LatestPostDate
    FROM 
        Tags t
    JOIN 
        Posts p ON t.TagName = ANY(string_to_array(p.Tags, '><'))
    GROUP BY 
        t.TagName
),
UserActivity AS (
    SELECT 
        u.Id,
        u.DisplayName,
        COUNT(p.Id) AS PostCount,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Comments c ON u.Id = c.UserId
    LEFT JOIN 
        Votes v ON u.Id = v.UserId
    GROUP BY 
        u.Id, u.DisplayName
)
SELECT 
    rp.Id,
    rp.PostTypeId,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.OwnerUserId,
    rp.OwnerDisplayName,
    rp.UserRank,
    rp.UpVotes,
    rp.DownVotes,
    rp.CommentCount,
    rp.LastEditDate,
    ts.TagName,
    ts.PostCount AS TagPostCount,
    ts.AvgScore AS TagAvgScore,
    ua.CommentCount AS UserCommentCount,
    ua.TotalUpVotes,
    ua.TotalDownVotes
FROM 
    RankedPosts rp
JOIN 
    TopPosters tp ON rp.OwnerUserId = tp.OwnerUserId
JOIN 
    TagStats ts ON rp.Tags LIKE '%' || ts.TagName || '%'
JOIN 
    UserActivity ua ON rp.OwnerUserId = ua.Id
WHERE 
    rp.Score > 0
    AND rp.ViewCount > 100
    AND rp.LastEditDate IS NOT NULL
ORDER BY 
    rp.Score DESC, 
    rp.ViewCount DESC, 
    ua.TotalUpVotes DESC
LIMIT 100;
