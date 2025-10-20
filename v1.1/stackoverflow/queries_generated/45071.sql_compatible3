WITH RankedUserPosts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.Score,
        p.Tags,
        p.PostTypeId,
        DENSE_RANK() OVER (PARTITION BY u.Id ORDER BY p.Score DESC) AS ScoreRank,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) OVER (PARTITION BY u.Id) AS UpVoteCount
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.CreationDate > DATE '2015-01-01'
),
TagBreakdown AS (
    SELECT 
        rup.UserId,
        rup.DisplayName,
        (
            SELECT ARRAY_AGG(tag ORDER BY tag)
            FROM (
                SELECT DISTINCT TRIM(tag) AS tag
                FROM (
                    SELECT regexp_split_to_table(
                        CASE 
                            WHEN rup.Tags IS NULL THEN ''
                            WHEN SUBSTR(rup.Tags,1,1) = '<' AND SUBSTR(rup.Tags, -1, 1) = '>' THEN SUBSTR(rup.Tags, 2, LENGTH(rup.Tags)-2)
                            ELSE rup.Tags
                        END,
                        '><'
                    ) AS tag
                ) s1
                WHERE tag <> ''
            ) s2
        ) AS UniqueTagsList
    FROM RankedUserPosts rup
    WHERE rup.ScoreRank <= 3
    GROUP BY rup.UserId, rup.DisplayName, rup.Tags
)
SELECT 
    t.DisplayName,
    t.UserId,
    COALESCE(CARDINALITY(t.UniqueTagsList), 0) AS UniqueTagCount,
    ROUND(AVG(r.Score)::numeric, 2) AS AvgTopPostScore,
    MAX(r.UpVoteCount) AS MaxUpVotes,
    COUNT(DISTINCT r.PostId) AS TopPostCount
FROM TagBreakdown t
JOIN RankedUserPosts r ON t.UserId = r.UserId
WHERE r.ScoreRank <= 3 AND r.PostTypeId = 1
GROUP BY t.UserId, t.DisplayName, t.UniqueTagsList
ORDER BY MaxUpVotes DESC, AvgTopPostScore DESC
LIMIT 100;