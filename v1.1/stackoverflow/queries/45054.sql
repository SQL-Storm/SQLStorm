-- {"query": "45054.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3.5-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 414}
WITH RankedQuestions AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.Score, 
        p.ViewCount,
        p.Tags,
        u.Reputation,
        DENSE_RANK() OVER (PARTITION BY EXTRACT(YEAR FROM p.CreationDate) ORDER BY p.Score DESC) as YearlyScoreRank,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) OVER (PARTITION BY p.Id) as UpVoteCount,
        COUNT(c.Id) OVER (PARTITION BY p.Id) as CommentCount,
        ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC, p.Score DESC) as GlobalPopularityRank
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    WHERE 
        p.PostTypeId = 1 
        AND p.CreationDate > '2015-01-01'
        AND u.Reputation > 1000
)
SELECT 
    Title,
    Score,
    ViewCount,
    Reputation,
    YearlyScoreRank,
    UpVoteCount,
    CommentCount,
    GlobalPopularityRank
FROM 
    RankedQuestions
WHERE 
    YearlyScoreRank <= 10
    AND GlobalPopularityRank <= 500
ORDER BY 
    GlobalPopularityRank, 
    Score DESC
LIMIT 100;
