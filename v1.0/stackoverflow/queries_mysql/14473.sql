
WITH PostStatistics AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        u.Reputation AS OwnerReputation,
        COUNT(c.Id) AS TotalComments,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownVotes
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.CreationDate >= '2023-01-01' 
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, u.Reputation
),
Ranking AS (
    SELECT 
        PostId,
        Title,
        CreationDate,
        Score,
        ViewCount,
        AnswerCount,
        CommentCount,
        OwnerReputation,
        TotalComments,
        TotalUpVotes,
        TotalDownVotes,
        @scoreRank := IF(@prevScore = Score, @scoreRank, @rank := @rank + 1) AS ScoreRank,
        @prevScore := Score,
        @answerRank := IF(@prevAnswerCount = AnswerCount, @answerRank, @rank := @rank + 1) AS AnswerRank,
        @prevAnswerCount := AnswerCount
    FROM 
        PostStatistics, (SELECT @scoreRank := 0, @answerRank := 0, @prevScore := NULL, @prevAnswerCount := NULL) AS vars
    ORDER BY 
        Score DESC, ViewCount DESC, AnswerCount DESC
)

SELECT 
    PostId,
    Title,
    CreationDate,
    Score,
    ViewCount,
    AnswerCount,
    CommentCount,
    OwnerReputation,
    TotalComments,
    TotalUpVotes,
    TotalDownVotes,
    ScoreRank,
    AnswerRank
FROM 
    Ranking
ORDER BY 
    ScoreRank, AnswerRank;
