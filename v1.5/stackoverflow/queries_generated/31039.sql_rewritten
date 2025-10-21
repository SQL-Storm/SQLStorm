-- {"query": "31039.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 501} 
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS Rank
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '1 year'
        AND p.PostTypeId IN (1, 2) -- Considering Questions and Answers
),
AggregatedVoteStats AS (
    SELECT 
        v.PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
        COUNT(*) AS TotalVotes 
    FROM 
        Votes v
    GROUP BY 
        v.PostId
),
PostHistoryStats AS (
    SELECT 
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 11) THEN 1 END) AS CloseRevisions,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 24 THEN 1 END) AS SuggestedEdits
    FROM 
        PostHistory ph
    GROUP BY 
        ph.PostId
)
SELECT 
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.OwnerDisplayName,
    rp.OwnerReputation,
    COALESCE(avs.UpVotes, 0) AS UpVotes,
    COALESCE(avs.DownVotes, 0) AS DownVotes,
    COALESCE(avs.TotalVotes, 0) AS TotalVotes,
    COALESCE(phs.CloseRevisions, 0) AS CloseRevisions,
    COALESCE(phs.SuggestedEdits, 0) AS SuggestedEdits,
    rp.Rank
FROM 
    RankedPosts rp
LEFT JOIN 
    AggregatedVoteStats avs ON rp.PostId = avs.PostId
LEFT JOIN 
    PostHistoryStats phs ON rp.PostId = phs.PostId
WHERE 
    rp.Rank <= 5
ORDER BY 
    rp.Rank;