-- {"query": "31032.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 352} 
WITH RankedVotes AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        v.VoteTypeId,
        v.UserId,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY v.CreationDate DESC) AS VoteRank
    FROM 
        Posts p
    JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        v.VoteTypeId IN (2, 3)  -- UpMod and DownMod votes
),
TotalVotes AS (
    SELECT
        PostId,
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM
        RankedVotes
    GROUP BY
        PostId
),
TopPost AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        tv.UpVotes,
        tv.DownVotes,
        (tv.UpVotes - tv.DownVotes) AS Score,
        ROW_NUMBER() OVER (ORDER BY (tv.UpVotes - tv.DownVotes) DESC) AS Rank
    FROM 
        Posts p
    JOIN 
        TotalVotes tv ON p.Id = tv.PostId
    WHERE
        p.PostTypeId = 1  -- Only questions
)
SELECT 
    tp.PostId,
    tp.Title,
    tp.CreationDate,
    tp.UpVotes,
    tp.DownVotes,
    tp.Score
FROM 
    TopPost tp
WHERE 
    tp.Rank <= 10
ORDER BY 
    tp.Score DESC;