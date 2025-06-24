
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        COUNT(a.Id) AS AnswerCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes, 
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes, 
        ROW_NUMBER() OVER (PARTITION BY p.Tags ORDER BY p.CreationDate DESC) AS Rank
    FROM
        Posts p
    LEFT JOIN
        Posts a ON p.Id = a.ParentId
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    WHERE
        p.PostTypeId = 1  
    GROUP BY
        p.Id, p.Title, p.CreationDate, p.Tags, p.OwnerUserId, p.AcceptedAnswerId
),
PopularTags AS (
    SELECT
        TRIM(tag) AS Tag
    FROM
        Posts b,
        (SELECT SUBSTRING_INDEX(SUBSTRING_INDEX(b.Tags, ',', numbers.n), ',', -1) AS tag
         FROM (SELECT 1 n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 
               UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 
               UNION ALL SELECT 9 UNION ALL SELECT 10) numbers
         WHERE CHAR_LENGTH(b.Tags) - CHAR_LENGTH(REPLACE(b.Tags, ',', '')) >= numbers.n - 1) 
    AS tags
    WHERE
        b.PostTypeId = 1  
),
TopUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        SUM(p.ViewCount) AS TotalViews,
        SUM(rp.UpVotes) AS TotalUpVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts
    FROM
        Users u
    JOIN
        Posts p ON u.Id = p.OwnerUserId
    JOIN
        RankedPosts rp ON p.Id = rp.PostId
    WHERE
        p.CreationDate >= '2023-01-01'  
    GROUP BY
        u.Id, u.DisplayName
    ORDER BY
        TotalViews DESC
    LIMIT 10
)

SELECT
    rp.Title,
    rp.CreationDate,
    rp.Tags,
    tu.DisplayName AS TopUser,
    rp.AnswerCount,
    rp.UpVotes,
    rp.DownVotes,
    pt.Tag AS PopularTag
FROM
    RankedPosts rp
JOIN
    TopUsers tu ON rp.OwnerUserId = tu.UserId
JOIN
    PopularTags pt ON rp.Tags LIKE CONCAT('%', pt.Tag, '%')  
WHERE
    rp.Rank <= 5  
ORDER BY
    rp.CreationDate DESC;
