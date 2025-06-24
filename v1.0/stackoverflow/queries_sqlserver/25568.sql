
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        p.Tags,
        COUNT(DISTINCT c.Id) AS CommentCount,
        RANK() OVER (PARTITION BY p.Id ORDER BY p.ViewCount DESC) AS RankByViews
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    WHERE 
        p.CreationDate >= DATEADD(YEAR, -1, '2024-10-01 12:34:56')
    GROUP BY 
        p.Id, p.Title, p.Body, p.CreationDate, p.ViewCount, p.Score, p.Tags
),
TagUsage AS (
    SELECT 
        value AS TagName,
        COUNT(*) AS TagCount
    FROM 
        Posts p
    CROSS APPLY STRING_SPLIT(SUBSTRING(p.Tags, 2, LEN(p.Tags) - 2), '><')
    WHERE 
        p.PostTypeId = 1 
        AND p.CreationDate >= DATEADD(MONTH, -6, '2024-10-01 12:34:56')
    GROUP BY 
        value
    ORDER BY 
        TagCount DESC
    OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY
),
UserParticipation AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostsCreated,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswers
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        u.CreationDate >= DATEADD(YEAR, -1, '2024-10-01 12:34:56')
    GROUP BY 
        u.Id, u.DisplayName
)
SELECT 
    rp.Title,
    rp.ViewCount,
    rp.Score,
    tu.TagName,
    up.DisplayName,
    up.PostsCreated,
    up.AnswersProvided,
    up.AcceptedAnswers
FROM 
    RankedPosts rp
LEFT JOIN 
    TagUsage tu ON rp.Tags LIKE '%' + tu.TagName + '%'
LEFT JOIN 
    UserParticipation up ON rp.PostId = (
        SELECT TOP 1 p.Id 
        FROM Posts p 
        WHERE p.OwnerUserId = up.UserId 
        ORDER BY p.CreationDate ASC
    )
WHERE 
    rp.RankByViews <= 5
ORDER BY 
    rp.ViewCount DESC, 
    rp.Score DESC;
