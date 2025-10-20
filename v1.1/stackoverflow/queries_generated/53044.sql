-- {"query": "53044.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 792} 
WITH TopQuestions AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY p.Score DESC) AS Rank
    FROM 
        Posts p
    INNER JOIN 
        Tags t ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE 
        p.PostTypeId = 1
        AND p.CreationDate >= '2020-01-01'
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id, u.Reputation, u.UpVotes, u.DownVotes
),
VoteSummary AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
        COUNT(DISTINCT v.Id) AS TotalVotes
    FROM 
        Votes v
    GROUP BY 
        v.PostId
),
EditHistory AS (
    SELECT 
        ph.PostId,
        COUNT(DISTINCT ph.Id) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM 
        PostHistory ph
    WHERE 
        ph.PostHistoryTypeId IN (4,5,6,7,8,9)
    GROUP BY 
        ph.PostId
),
CommentStats AS (
    SELECT 
        c.PostId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore
    FROM 
        Comments c
    GROUP BY 
        c.PostId
),
LinkedPosts AS (
    SELECT 
        pl.PostId,
        COUNT(DISTINCT pl.RelatedPostId) AS LinkedCount
    FROM 
        PostLinks pl
    GROUP BY 
        pl.PostId
)
SELECT 
    tq.QuestionId,
    tq.Title,
    tq.Score,
    tq.ViewCount,
    tq.AnswerCount,
    tq.CommentCount AS QuestionCommentCount,
    tq.FavoriteCount,
    us.Reputation,
    us.BadgeCount,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    vs.Upvotes,
    vs.Downvotes,
    vs.TotalVotes,
    eh.EditCount,
    eh.LastEditDate,
    cs.CommentCount AS TotalComments,
    cs.AvgCommentScore,
    lp.LinkedCount
FROM 
    TopQuestions tq
INNER JOIN 
    UserStats us ON tq.OwnerUserId = us.UserId
LEFT JOIN 
    VoteSummary vs ON tq.QuestionId = vs.PostId
LEFT JOIN 
    EditHistory eh ON tq.QuestionId = eh.PostId
LEFT JOIN 
    CommentStats cs ON tq.QuestionId = cs.PostId
LEFT JOIN 
    LinkedPosts lp ON tq.QuestionId = lp.PostId
WHERE 
    tq.Rank = 1
ORDER BY 
    tq.Score DESC
LIMIT 100;