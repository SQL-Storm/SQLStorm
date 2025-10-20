WITH UserTagActivity AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName,
        tag_list.TagName,
        COUNT(p.Id) AS PostCount,
        AVG(p.Score) AS AvgPostScore,
        SUM(v.VoteCount) AS TotalVotes
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    JOIN 
        (SELECT PostId, COUNT(*) AS VoteCount 
         FROM Votes 
         WHERE VoteTypeId IN (2, 3) 
         GROUP BY PostId) v ON p.Id = v.PostId
    JOIN LATERAL (
        SELECT value AS TagName
        FROM UNNEST(
            REGEXP_SPLIT_TO_ARRAY(
                SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2),
                '><'
            )
        ) AS t(value)
    ) AS tag_list ON TRUE
    JOIN 
        Tags t ON tag_list.TagName = t.TagName
    WHERE 
        p.PostTypeId = 1
        AND u.Reputation > 1000
    GROUP BY 
        u.Id, u.DisplayName, tag_list.TagName
    HAVING 
        COUNT(p.Id) > 5
),
RankedUserTags AS (
    SELECT 
        UserId, 
        DisplayName,
        TagName,
        PostCount,
        AvgPostScore,
        TotalVotes,
        DENSE_RANK() OVER (PARTITION BY UserId ORDER BY PostCount DESC) AS TagRank
    FROM 
        UserTagActivity
)
SELECT 
    DisplayName,
    TagName,
    PostCount,
    AvgPostScore,
    TotalVotes
FROM 
    RankedUserTags
WHERE 
    TagRank <= 3
ORDER BY 
    PostCount DESC, 
    TotalVotes DESC
LIMIT 100;