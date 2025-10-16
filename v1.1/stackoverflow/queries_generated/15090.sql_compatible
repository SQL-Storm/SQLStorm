WITH RankedUserPosts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        p.Id AS PostId,
        p.Score,
        p.PostTypeId,
        p.Tags,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.Score DESC) AS PostRank,
        AVG(p.Score) OVER (PARTITION BY u.Id) AS UserAvgPostScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id) AS UserAnswerCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE 
        u.Reputation > 1000 
        AND p.CreationDate > DATE '2015-01-01'
        AND (p.Tags LIKE '%<sql>%' OR p.Tags LIKE '%<database>%')
),
PostVoteSummary AS (
    SELECT 
        PostId,
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(*) AS TotalVotes
    FROM Votes
    GROUP BY PostId
)
SELECT 
    rp.UserId,
    rp.DisplayName,
    rp.PostId,
    rp.Score,
    COALESCE(vs.UpVotes, 0) - COALESCE(vs.DownVotes, 0) AS NetVotes,
    rp.UserAvgPostScore,
    rp.UserAnswerCount,
    CASE 
        WHEN rp.Score > rp.UserAvgPostScore * 1.5 THEN 'High Performance'
        WHEN rp.Score < rp.UserAvgPostScore * 0.5 THEN 'Low Performance'
        ELSE 'Average Performance'
    END AS PostPerformanceCategory,
    NULLIF(REGEXP_REPLACE(rp.Tags, '[<>]', '', 'g'), '') AS CleanTags
FROM RankedUserPosts rp
LEFT JOIN PostVoteSummary vs ON rp.PostId = vs.PostId
WHERE 
    rp.PostRank <= 3
    AND (vs.TotalVotes > 5 OR vs.TotalVotes IS NULL)
GROUP BY
    rp.UserId,
    rp.DisplayName,
    rp.PostId,
    rp.Score,
    vs.UpVotes,
    vs.DownVotes,
    vs.TotalVotes,
    rp.UserAvgPostScore,
    rp.UserAnswerCount,
    rp.Tags,
    rp.PostRank
ORDER BY 
    NetVotes DESC,
    rp.UserAvgPostScore DESC
LIMIT 100;