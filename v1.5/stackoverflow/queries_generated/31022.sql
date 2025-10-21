-- {"query": "31022.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 350} 

WITH RankedPosts AS (
    SELECT 
        P.Id AS PostId,
        P.Title,
        U.DisplayName AS Author,
        P.CreationDate,
        P.ViewCount,
        P.Score,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate DESC) AS PostRank,
        COUNT(CASE WHEN C.Id IS NOT NULL THEN 1 END) AS CommentCount,
        COUNT(V.Id) FILTER (WHERE V.VoteTypeId = 2) AS UpVoteCount,
        COUNT(V.Id) FILTER (WHERE V.VoteTypeId = 3) AS DownVoteCount
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    LEFT JOIN 
        Comments C ON P.Id = C.PostId
    LEFT JOIN 
        Votes V ON P.Id = V.PostId
    WHERE 
        P.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY 
        P.Id, U.DisplayName 
),
TopPosts AS (
    SELECT 
        PostId,
        Title,
        Author,
        ViewCount,
        Score,
        CommentCount,
        UpVoteCount,
        DownVoteCount,
        CASE 
            WHEN PostRank = 1 THEN 'Latest Post'
            ELSE 'Other Posts'
        END AS PostType
    FROM 
        RankedPosts
)
SELECT 
    PostId,
    Title,
    Author,
    ViewCount,
    Score,
    CommentCount,
    UpVoteCount,
    DownVoteCount,
    PostType
FROM 
    TopPosts
ORDER BY 
    ViewCount DESC, Score DESC
LIMIT 10;
