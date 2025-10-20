-- {"query": "31023.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 533} 

WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.CreationDate,
        p.ViewCount,
        COUNT(c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        ROW_NUMBER() OVER (PARTITION BY pt.Name ORDER BY p.ViewCount DESC) AS RankByViews,
        ROW_NUMBER() OVER (PARTITION BY pt.Name ORDER BY p.Score DESC) AS RankByScore
    FROM 
        Posts p
    JOIN 
        PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.CreationDate > NOW() - INTERVAL '1 YEAR'
    GROUP BY 
        p.Id, p.Title, p.Score, p.CreationDate, p.ViewCount, pt.Name
),
TopQuestions AS (
    SELECT 
        PostId,
        Title,
        Score,
        ViewCount,
        CommentCount,
        RankByViews
    FROM 
        RankedPosts 
    WHERE 
        RankByViews <= 5
),
TopAnswers AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        COUNT(c.Id) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC) AS Rank
    FROM 
        Posts p
    JOIN 
        Posts q ON p.ParentId = q.Id AND q.PostTypeId = 1
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    WHERE 
        p.PostTypeId = 2 AND p.CreationDate > NOW() - INTERVAL '1 YEAR'
    GROUP BY 
        p.Id, p.Title, p.Score, p.ViewCount, p.ParentId
)
SELECT 
    tq.PostId AS TopQuestionId,
    tq.Title AS TopQuestionTitle,
    tq.Score AS TopQuestionScore,
    tq.ViewCount AS TopQuestionViewCount,
    tq.CommentCount AS TopQuestionCommentCount,
    ta.PostId AS TopAnswerId,
    ta.Title AS TopAnswerTitle,
    ta.Score AS TopAnswerScore,
    ta.ViewCount AS TopAnswerViewCount,
    ta.CommentCount AS TopAnswerCommentCount
FROM 
    TopQuestions tq
LEFT JOIN 
    TopAnswers ta ON tq.PostId = ta.ParentId
ORDER BY 
    tq.Score DESC, tq.ViewCount DESC;
