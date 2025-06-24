
WITH RankedPosts AS (
    SELECT 
        P.Id AS PostId,
        P.Title,
        P.ViewCount,
        P.AnswerCount,
        P.CreationDate,
        P.Score,
        U.Reputation AS OwnerReputation,
        RANK() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC) AS ScoreRank
    FROM 
        Posts P
    JOIN 
        Users U ON P.OwnerUserId = U.Id
    WHERE 
        P.CreationDate >= NOW() - INTERVAL 1 YEAR
        AND P.PostTypeId = 1  
),
TopPosts AS (
    SELECT 
        PostId,
        Title,
        ViewCount,
        AnswerCount,
        CreationDate,
        Score,
        OwnerReputation
    FROM 
        RankedPosts
    WHERE 
        ScoreRank <= 5  
),
PostTagStats AS (
    SELECT 
        P.Id AS PostId,
        COUNT(DISTINCT T.TagName) AS TagCount,
        GROUP_CONCAT(DISTINCT T.TagName ORDER BY T.TagName ASC SEPARATOR ', ') AS Tags
    FROM 
        Posts P
    JOIN 
        (SELECT TRIM(tag) AS tag FROM Posts, JSON_TABLE(CONCAT('["', REPLACE(P.Tags, '>', '","'), '"]'), '$[*]' COLUMNS (tag VARCHAR(255) PATH '$')) AS tag) AS tag ON tag IS NOT NULL
    JOIN 
        Tags T ON T.TagName = tag.tag
    GROUP BY 
        P.Id
),
CombinedStats AS (
    SELECT 
        TP.PostId,
        TP.Title,
        TP.ViewCount,
        TP.AnswerCount,
        TP.CreationDate,
        TP.Score,
        TP.OwnerReputation,
        PTS.TagCount,
        PTS.Tags
    FROM 
        TopPosts TP
    LEFT JOIN 
        PostTagStats PTS ON TP.PostId = PTS.PostId
)
SELECT 
    PostId,
    Title,
    ViewCount,
    AnswerCount,
    CreationDate,
    Score,
    OwnerReputation,
    TagCount,
    Tags
FROM 
    CombinedStats
ORDER BY 
    Score DESC,
    CreationDate DESC;
