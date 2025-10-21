-- {"query": "15032.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 77055, "output_tokens": 23221} 
WITH PostQualityMetrics AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        u.Reputation,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        DENSE_RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS ScoreRank,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS UserPostSequence
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.CreationDate > '2015-01-01'
        AND p.PostTypeId IN (1, 2)
),
VoteSummary AS (
    SELECT 
        PostId,
        COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS DownVotes,
        SUM(CASE WHEN VoteTypeId = 8 THEN BountyAmount ELSE 0 END) AS TotalBountyAmount
    FROM 
        Votes
    GROUP BY 
        PostId
)
SELECT 
    pqm.PostId,
    pqm.PostTypeId,
    pqm.Score,
    pqm.ViewCount,
    pqm.CommentCount,
    pqm.Reputation,
    pqm.AnswerCount,
    pqm.ScoreRank,
    pqm.UserPostSequence,
    vs.UpVotes,
    vs.DownVotes,
    vs.TotalBountyAmount,
    CASE 
        WHEN pqm.Score > 10 AND vs.UpVotes > 5 THEN 'High Quality'
        WHEN pqm.Score BETWEEN 0 AND 10 AND vs.UpVotes BETWEEN 1 AND 5 THEN 'Moderate Quality'
        ELSE 'Low Quality'
    END AS PostQuality,
    (vs.UpVotes - vs.DownVotes) / NULLIF(pqm.ViewCount, 0)::float AS VoteEngagementRatio
FROM 
    PostQualityMetrics pqm
JOIN 
    VoteSummary vs ON pqm.PostId = vs.PostId
WHERE 
    pqm.Reputation > 100
    AND (
        (pqm.PostTypeId = 1 AND pqm.AnswerCount > 0)
        OR 
        (pqm.PostTypeId = 2 AND EXISTS (
            SELECT 1 
            FROM Posts parent 
            WHERE parent.Id = pqm.ParentId 
              AND parent.PostTypeId = 1
        ))
    )
ORDER BY 
    VoteEngagementRatio DESC
LIMIT 1000;