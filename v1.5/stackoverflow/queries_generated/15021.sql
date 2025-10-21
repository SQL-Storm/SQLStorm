-- {"query": "15021.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 773}
WITH TagRankings AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        t.TagName,
        COUNT(v.Id) AS VoteCount,
        DENSE_RANK() OVER (PARTITION BY t.TagName ORDER BY COUNT(v.Id) DESC) AS TagVoteRank,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY v.CreationDate DESC) AS LatestVoteOrder
    FROM 
        Posts p
    JOIN 
        Tags t ON p.Tags LIKE '%' || t.TagName || '%'
    LEFT JOIN 
        Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    WHERE 
        p.PostTypeId = 1 
        AND p.CreationDate > TIMESTAMP '2015-01-01'
        AND p.ViewCount > 100
    GROUP BY 
        p.Id, p.Title, t.TagName, v.CreationDate
), 
UserTagPerformance AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        tr.TagName,
        AVG(p.Score) AS AvgTagScore,
        COUNT(DISTINCT p.Id) AS PostCount,
        MAX(CASE WHEN tr.TagVoteRank = 1 THEN 1 ELSE 0 END) AS TopRankedPost
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    JOIN 
        TagRankings tr ON p.Id = tr.PostId
    WHERE 
        u.Reputation > 1000
    GROUP BY 
        u.Id, u.DisplayName, tr.TagName
)
SELECT 
    utp.UserId,
    utp.DisplayName,
    utp.TagName,
    utp.AvgTagScore,
    utp.PostCount,
    COALESCE(b.Name, 'No Badge') AS TopBadge,
    CASE 
        WHEN utp.TopRankedPost = 1 THEN 'Top Performer'
        WHEN utp.PostCount > 10 THEN 'Active Contributor'
        ELSE 'Emerging Contributor'
    END AS ContributorCategory,
    NULLIF(
        (SELECT COUNT(*) 
         FROM PostLinks pl 
         WHERE EXISTS (
             SELECT 1 
             FROM Posts p 
             WHERE p.Id = pl.PostId AND p.Tags LIKE '%' || utp.TagName || '%'
         )), 0) AS RelatedPostCount
FROM 
    UserTagPerformance utp
LEFT JOIN LATERAL (
    SELECT Name 
    FROM Badges 
    WHERE UserId = utp.UserId 
    ORDER BY Class ASC 
    LIMIT 1
) b ON TRUE
WHERE 
    utp.AvgTagScore > 2
    AND utp.PostCount > 5
ORDER BY 
    utp.AvgTagScore DESC, 
    utp.PostCount DESC
LIMIT 100;
