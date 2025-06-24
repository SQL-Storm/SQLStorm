
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CreationDate,
        @rownum := IF(@prev = pt.Name, @rownum + 1, 1) AS Rank,
        @prev := pt.Name,
        U.DisplayName AS OwnerDisplayName,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id), 0) AS UpVoteCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id), 0) AS DownVoteCount
    FROM 
        Posts p
    JOIN 
        PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN 
        Users U ON p.OwnerUserId = U.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId,
        (SELECT @rownum := 0, @prev := '') AS r
    WHERE 
        p.CreationDate >= NOW() - INTERVAL 1 YEAR
    ORDER BY 
        pt.Name, p.Score DESC, p.CreationDate DESC
)

SELECT 
    r.PostId,
    r.Title,
    r.Score,
    r.ViewCount,
    r.AnswerCount,
    r.OwnerDisplayName,
    r.UpVoteCount,
    r.DownVoteCount,
    r.Rank
FROM 
    RankedPosts r
WHERE 
    r.Rank <= 5
ORDER BY 
    r.Score DESC, r.ViewCount DESC;
