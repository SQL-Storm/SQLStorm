WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.CreationDate,
        p.ViewCount,
        COALESCE(p.Score, 0) AS PostScore,
        ARRAY_AGG(DISTINCT t.TagName) AS Tags,
        ROW_NUMBER() OVER (ORDER BY COALESCE(p.Score, 0) DESC, p.CreationDate DESC) AS Rank
    FROM 
        Posts p
    LEFT JOIN 
        Tags t ON t.WikiPostId = p.Id OR t.ExcerptPostId = p.Id
    WHERE 
        p.PostTypeId = 1  -- Only questions
    GROUP BY 
        p.Id, p.Title, p.Body, p.CreationDate, p.ViewCount
),
PopularTags AS (
    SELECT 
        unnest(R.Tags) AS Tag,
        COUNT(*) AS TagCount
    FROM 
        RankedPosts R
    WHERE 
        R.Rank <= 100  -- Considering only top 100 scored questions
    GROUP BY 
        Tag
),
TopUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        SUM(COALESCE(v.BountyAmount, 0)) AS TotalBounty,
        SUM(COALESCE(v.UserId, 0) DECODE(v.VoteTypeId, 2, 1, -1, 0)) AS TotalScore
    FROM 
        Users u
    LEFT JOIN 
        Votes v ON u.Id = v.UserId
    GROUP BY 
        u.Id, u.DisplayName
    ORDER BY 
        TotalScore DESC 
    LIMIT 50  -- Top 50 users based on scores
)
SELECT 
    RP.PostId,
    RP.Title,
    RP.ViewCount,
    RP.PostScore,
    PT.Tag,
    TU.DisplayName AS TopUser,
    TU.TotalBounty
FROM 
    RankedPosts RP
JOIN 
    PopularTags PT ON PT.Tag = ANY(RP.Tags)
JOIN 
    TopUsers TU ON TU.TotalBounty > 100
ORDER BY 
    RP.PostScore DESC, PT.TagCount DESC, TU.TotalBounty DESC;
