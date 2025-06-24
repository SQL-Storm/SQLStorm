
WITH TagPostCounts AS (
    SELECT 
        value AS TagName,
        COUNT(*) AS PostCount
    FROM 
        Posts
    CROSS APPLY STRING_SPLIT(SUBSTRING(Tags, 2, LEN(Tags) - 2), '><') 
    WHERE 
        PostTypeId = 1  
    GROUP BY 
        value
),
UserMetrics AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        SUM(ISNULL(v.BountyAmount, 0)) AS TotalBounties,
        SUM(u.UpVotes) AS TotalUpVotes,
        SUM(u.DownVotes) AS TotalDownVotes
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN 
        Votes v ON u.Id = v.UserId AND v.PostId IN (SELECT Id FROM Posts WHERE PostTypeId = 1)
    GROUP BY 
        u.Id, u.DisplayName
),
PopularTags AS (
    SELECT 
        tc.TagName,
        tc.PostCount,
        RANK() OVER (ORDER BY tc.PostCount DESC) AS PopularityRank
    FROM 
        TagPostCounts tc
    WHERE 
        tc.PostCount > 5  
),
UserTagIntersections AS (
    SELECT 
        um.UserId,
        mt.TagName
    FROM 
        UserMetrics um
    JOIN 
        PopularTags mt ON um.QuestionCount > 0  
)
SELECT 
    ut.UserId,
    u.DisplayName,
    STRING_AGG(DISTINCT ut.TagName, ', ') AS PopularTags,
    SUM(um.TotalBounties) AS SumOfBounties,
    SUM(um.TotalUpVotes) AS UpVoteSum,
    SUM(um.TotalDownVotes) AS DownVoteSum
FROM 
    UserTagIntersections ut
JOIN 
    UserMetrics um ON ut.UserId = um.UserId
JOIN 
    Users u ON um.UserId = u.Id
GROUP BY 
    ut.UserId, u.DisplayName
ORDER BY 
    UpVoteSum DESC, SumOfBounties DESC
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;
