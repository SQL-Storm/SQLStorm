
WITH PostTags AS (
    SELECT 
        p.Id AS PostId,
        value AS Tag
    FROM 
        Posts p 
    CROSS APPLY 
        STRING_SPLIT(SUBSTRING(p.Tags, 2, LEN(p.Tags)-2), '><') 
    WHERE 
        p.PostTypeId = 1 
),
UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        SUM(ISNULL(v.Direction, 0)) AS TotalVotes,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN 
        (SELECT 
            PostId, 
            COUNT(VoteTypeId) AS Direction
         FROM 
            Votes 
         WHERE 
            VoteTypeId IN (2, 3) 
         GROUP BY 
            PostId) v ON v.PostId = p.Id
    LEFT JOIN 
        Badges b ON b.UserId = u.Id
    GROUP BY 
        u.Id, u.DisplayName
),
MostActiveTags AS (
    SELECT 
        pt.Tag,
        COUNT(pt.PostId) AS TagUsage
    FROM 
        PostTags pt
    GROUP BY 
        pt.Tag
)
SELECT TOP 10
    u.DisplayName AS UserName,
    u.QuestionCount,
    u.TotalVotes,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    mt.Tag AS MostUsedTag,
    mt.TagUsage
FROM 
    UserPostStats u
CROSS JOIN 
    MostActiveTags mt
ORDER BY 
    u.TotalVotes DESC, u.QuestionCount DESC;
