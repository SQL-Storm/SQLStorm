-- {"query": "53019.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 653} 
WITH TopQuestions AS (
    SELECT 
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.Score AS QuestionScore,
        p.ViewCount,
        p.AnswerCount,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY p.Score DESC) AS Rank
    FROM 
        Posts p
    INNER JOIN 
        Tags t ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE 
        p.PostTypeId = 1  -- Questions
        AND t.Count > 1000
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        AVG(v.BountyAmount) AS AvgBounty
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    LEFT JOIN 
        Votes v ON u.Id = v.UserId AND v.VoteTypeId = 8  -- BountyStart
    GROUP BY 
        u.Id, u.Reputation
    HAVING 
        COUNT(DISTINCT b.Id) > 10
),
AnswerDetails AS (
    SELECT 
        a.ParentId AS QuestionId,
        MAX(a.Score) AS TopAnswerScore,
        COUNT(c.Id) AS CommentCount
    FROM 
        Posts a
    LEFT JOIN 
        Comments c ON a.Id = c.PostId
    WHERE 
        a.PostTypeId = 2  -- Answers
    GROUP BY 
        a.ParentId
)
SELECT 
    tq.QuestionId,
    tq.OwnerUserId,
    us.Reputation,
    us.BadgeCount,
    us.GoldBadges,
    us.AvgBounty,
    tq.QuestionScore,
    tq.ViewCount,
    tq.AnswerCount,
    ad.TopAnswerScore,
    ad.CommentCount,
    COUNT(DISTINCT ph.Id) AS EditCount,
    COUNT(DISTINCT pl.RelatedPostId) AS LinkedPosts,
    COUNT(DISTINCT v.Id) AS VoteCount
FROM 
    TopQuestions tq
INNER JOIN 
    UserStats us ON tq.OwnerUserId = us.UserId
LEFT JOIN 
    AnswerDetails ad ON tq.QuestionId = ad.QuestionId
LEFT JOIN 
    PostHistory ph ON tq.QuestionId = ph.PostId AND ph.PostHistoryTypeId IN (4,5,6)  -- Edits
LEFT JOIN 
    PostLinks pl ON tq.QuestionId = pl.PostId
LEFT JOIN 
    Votes v ON tq.QuestionId = v.PostId
WHERE 
    tq.Rank <= 10
GROUP BY 
    tq.QuestionId, tq.OwnerUserId, us.Reputation, us.BadgeCount, us.GoldBadges, us.AvgBounty, tq.QuestionScore, tq.ViewCount, tq.AnswerCount, ad.TopAnswerScore, ad.CommentCount
ORDER BY 
    tq.QuestionScore DESC, us.Reputation DESC
LIMIT 100;