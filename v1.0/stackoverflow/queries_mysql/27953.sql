
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Tags,
        p.Body,
        p.CreationDate,
        p.ViewCount,
        u.DisplayName AS OwnerDisplayName,
        COUNT(c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        @row_number := IF(@prev_post_type_id = p.PostTypeId, @row_number + 1, 1) AS Rank,
        @prev_post_type_id := p.PostTypeId
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    CROSS JOIN 
        (SELECT @row_number := 0, @prev_post_type_id := NULL) AS vars
    WHERE 
        p.CreationDate >= '2023-01-01' 
    GROUP BY 
        p.Id, p.Title, p.Tags, p.Body, p.CreationDate, p.ViewCount, u.DisplayName, p.Score
), AggregatedData AS (
    SELECT 
        PostId,
        Title,
        Tags,
        CreationDate,
        ViewCount,
        OwnerDisplayName,
        CommentCount,
        UpVotes,
        DownVotes,
        Rank
    FROM 
        RankedPosts
)
SELECT 
    ad.OwnerDisplayName,
    ad.Title,
    ad.Tags,
    ad.CreationDate,
    ad.ViewCount,
    ad.CommentCount,
    ad.UpVotes,
    ad.DownVotes,
    CASE 
        WHEN ad.Rank <= 10 THEN 'Top'
        ELSE 'Others'
    END AS PostRank,
    CASE 
        WHEN ad.Rank <= 10 THEN 'Excellent Engagement'
        ELSE 'Moderate Engagement'
    END AS EngagementLevel,
    GROUP_CONCAT(DISTINCT CONCAT(pt.Name, ': ', pt.Id) SEPARATOR ', ') AS PostTypeDetails
FROM 
    AggregatedData ad
JOIN 
    PostTypes pt ON ad.PostId = pt.Id 
GROUP BY 
    ad.OwnerDisplayName, ad.Title, ad.Tags, ad.CreationDate, ad.ViewCount, ad.CommentCount, ad.UpVotes, ad.DownVotes, ad.Rank
ORDER BY 
    ad.ViewCount DESC
LIMIT 100;
