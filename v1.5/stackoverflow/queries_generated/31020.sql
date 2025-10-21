-- {"query": "31020.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 408} 

WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        p.AnswerCount, 
        u.DisplayName AS OwnerName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS PostRank
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.CreationDate >= NOW() - INTERVAL '30 days'
      AND 
        p.PostTypeId IN (1, 2) -- Considering only Questions and Answers
), 
TopPostStats AS (
    SELECT 
        PostId, 
        Title, 
        CreationDate, 
        Score, 
        ViewCount, 
        AnswerCount, 
        OwnerName 
    FROM 
        RankedPosts 
    WHERE 
        PostRank <= 10
), 
VoteCount AS (
    SELECT 
        PostId, 
        COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS UpVotes, 
        COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS DownVotes
    FROM 
        Votes v
    JOIN 
        VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY 
        PostId
)
SELECT 
    t.Title, 
    t.CreationDate, 
    t.Score, 
    t.ViewCount, 
    t.AnswerCount, 
    t.OwnerName, 
    COALESCE(vc.UpVotes, 0) AS TotalUpVotes, 
    COALESCE(vc.DownVotes, 0) AS TotalDownVotes
FROM 
    TopPostStats t
LEFT JOIN 
    VoteCount vc ON t.PostId = vc.PostId
ORDER BY 
    t.Score DESC, t.ViewCount DESC;
