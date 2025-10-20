-- {"query": "1078.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 483} 

WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS Rank
    FROM 
        Posts p
    WHERE 
        p.CreationDate >= NOW() - INTERVAL '1 year'
),
TopPosts AS (
    SELECT 
        rp.PostId,
        rp.Title,
        rp.Score,
        rp.ViewCount,
        rp.AnswerCount,
        rp.CreationDate,
        CASE 
            WHEN rp.Score IS NULL THEN 'No Score'
            ELSE 'Scored'
        END AS ScoreStatus
    FROM 
        RankedPosts rp
    WHERE 
        rp.Rank <= 10
),
UserVotes AS (
    SELECT 
        v.PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
        COUNT(CASE WHEN v.VoteTypeId IN (2, 3) THEN 1 END) AS TotalVotes
    FROM 
        Votes v
    GROUP BY 
        v.PostId
),
PostDetails AS (
    SELECT 
        tp.PostId,
        tp.Title,
        tp.Score,
        tp.ViewCount,
        tp.AnswerCount,
        tp.CreationDate,
        COALESCE(uv.UpVotes, 0) AS UpVotes,
        COALESCE(uv.DownVotes, 0) AS DownVotes,
        tp.ScoreStatus
    FROM 
        TopPosts tp
    LEFT JOIN 
        UserVotes uv ON tp.PostId = uv.PostId
)
SELECT 
    pd.PostId,
    pd.Title,
    pd.Score,
    pd.ViewCount,
    pd.AnswerCount,
    pd.CreationDate,
    pd.UpVotes,
    pd.DownVotes,
    pd.ScoreStatus,
    'Posted on ' || to_char(pd.CreationDate, 'FMMonth DD, YYYY') AS FormattedDate
FROM 
    PostDetails pd
WHERE 
    pd.UpVotes > pd.DownVotes
ORDER BY 
    pd.ViewCount DESC
LIMIT 50;
