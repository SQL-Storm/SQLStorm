-- {"query": "43029.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 757} 

WITH RecentHighActivityUsers AS (
    SELECT 
        OwnerUserId,
        COUNT(*) AS PostCount,
        SUM(Score) AS TotalScore,
        AVG(ViewCount) AS AvgViewCount
    FROM 
        Posts
    WHERE 
        LastActivityDate > NOW() - INTERVAL '6 MONTHS' 
        AND OwnerUserId IS NOT NULL
    GROUP BY 
        OwnerUserId
    HAVING 
        COUNT(*) > 10
), TopTags AS (
    SELECT 
        TagName,
        COUNT(*) AS UsageCount
    FROM 
        Tags
        INNER JOIN Posts ON Posts.Tags LIKE CONCAT('%<', Tags.TagName, '>%')
    WHERE 
        Posts.CreationDate > NOW() - INTERVAL '1 YEAR'
    GROUP BY 
        TagName
    ORDER BY 
        UsageCount DESC
    LIMIT 10
), UserTagExpertise AS (
    SELECT 
        ph.UserId,
        t.TagName,
        COUNT(*) AS TagPostCount
    FROM 
        PostHistory ph
        INNER JOIN Posts p ON ph.PostId = p.Id
        INNER JOIN Tags t ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    WHERE 
        ph.PostHistoryTypeId IN (2, 5)
        AND t.TagName IN (SELECT TagName FROM TopTags)
    GROUP BY 
        ph.UserId, t.TagName
), UserReputationGrowth AS (
    SELECT 
        UserId,
        DATE_TRUNC('month', CreationDate) AS Month,
        AVG(Reputation) AS AvgMonthlyReputation
    FROM (
        SELECT 
            b.UserId,
            b.Date AS CreationDate,
            u.Reputation
        FROM 
            Badges b
            INNER JOIN Users u ON b.UserId = u.Id
        UNION ALL
        SELECT 
            p.OwnerUserId,
            p.CreationDate,
            u.Reputation
        FROM 
            Posts p
            INNER JOIN Users u ON p.OwnerUserId = u.Id
    ) AS Combined
    GROUP BY 
        UserId, Month
)
SELECT 
    u.DisplayName,
    u.Reputation,
    rau.PostCount,
    rau.TotalScore,
    rau.AvgViewCount,
    JSON_AGG(json_build_object('TagName', ute.TagName, 'TagPostCount', ute.TagPostCount)) AS TagExpertise,
    JSON_AGG(json_build_object('Month', urg.Month, 'AvgMonthlyReputation', urg.AvgMonthlyReputation)) AS ReputationGrowth
FROM 
    RecentHighActivityUsers rau
    INNER JOIN Users u ON rau.OwnerUserId = u.Id
    LEFT JOIN UserTagExpertise ute ON rau.OwnerUserId = ute.UserId
    LEFT JOIN UserReputationGrowth urg ON rau.OwnerUserId = urg.UserId
GROUP BY 
    u.DisplayName, u.Reputation, rau.PostCount, rau.TotalScore, rau.AvgViewCount
ORDER BY 
    rau.TotalScore DESC
LIMIT 50;
