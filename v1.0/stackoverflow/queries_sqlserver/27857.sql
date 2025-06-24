
WITH ProcessedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.Tags,
        U.DisplayName AS OwnerDisplayName,
        (
            SELECT COUNT(*) 
            FROM Votes 
            WHERE PostId = p.Id AND VoteTypeId = 2 
        ) AS UpVotes,
        (
            SELECT COUNT(*) 
            FROM Votes 
            WHERE PostId = p.Id AND VoteTypeId = 3 
        ) AS DownVotes,
        (
            SELECT COUNT(*) 
            FROM Comments 
            WHERE PostId = p.Id
        ) AS CommentCount,
        (
            SELECT COUNT(*) 
            FROM Posts 
            WHERE ParentId = p.Id
        ) AS AnswerCount,
        pt.Name AS PostType
    FROM 
        Posts p
    JOIN 
        Users U ON p.OwnerUserId = U.Id
    JOIN 
        PostTypes pt ON p.PostTypeId = pt.Id
    WHERE 
        p.CreationDate >= DATEADD(YEAR, -1, '2024-10-01 12:34:56') 
        AND p.Title IS NOT NULL 
        AND LEN(LTRIM(RTRIM(p.Body))) > 0 
),
RankedPosts AS (
    SELECT 
        PostId,
        Title,
        Body,
        Tags,
        OwnerDisplayName,
        UpVotes,
        DownVotes,
        CommentCount,
        AnswerCount,
        PostType,
        ROW_NUMBER() OVER (PARTITION BY PostType ORDER BY UpVotes DESC, AnswerCount DESC) AS Rank
    FROM 
        ProcessedPosts
)

SELECT 
    RP.PostId,
    RP.Title,
    RP.Body,
    RP.Tags,
    RP.OwnerDisplayName,
    RIGHT('00000' + CAST(RP.UpVotes AS VARCHAR(5)), 5) AS FormattedUpVotes,
    RIGHT('00000' + CAST(RP.DownVotes AS VARCHAR(5)), 5) AS FormattedDownVotes,
    RP.CommentCount,
    RP.AnswerCount,
    RP.PostType,
    RP.Rank
FROM 
    RankedPosts RP
WHERE 
    RP.Rank <= 10 
ORDER BY 
    RP.PostType, RP.Rank;
