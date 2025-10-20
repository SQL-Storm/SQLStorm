-- {"query": "53061.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 1048} 
WITH TagQuestions AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        p.Id AS PostId,
        p.Score AS QuestionScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9)) AS EditCount,
        COUNT(DISTINCT c.Id) AS CommentCountDetailed
    FROM 
        Tags t
    JOIN 
        Posts p ON p.PostTypeId = 1 AND p.Tags LIKE '%' || t.TagName || '%'
    LEFT JOIN 
        Votes v ON v.PostId = p.Id
    LEFT JOIN 
        PostHistory ph ON ph.PostId = p.Id
    LEFT JOIN 
        Comments c ON c.PostId = p.Id
    WHERE 
        p.CreationDate >= '2020-01-01' AND p.CreationDate < '2023-01-01'
    GROUP BY 
        t.Id, t.TagName, p.Id, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount
    HAVING 
        COUNT(DISTINCT v.Id) > 10
),
TopAnswersPerTag AS (
    SELECT 
        tq.TagId,
        tq.TagName,
        a.OwnerUserId,
        COUNT(a.Id) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        SUM(a.CommentCount) AS TotalAnswerComments,
        RANK() OVER (PARTITION BY tq.TagId ORDER BY COUNT(a.Id) DESC, AVG(a.Score) DESC) AS UserRank
    FROM 
        TagQuestions tq
    JOIN 
        Posts a ON a.ParentId = tq.PostId AND a.PostTypeId = 2
    GROUP BY 
        tq.TagId, tq.TagName, a.OwnerUserId
),
UserDetails AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId IN (4,5,6)) AS UserEdits
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON b.UserId = u.Id
    LEFT JOIN 
        PostHistory ph ON ph.UserId = u.Id
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation
),
LinkedPostsAnalysis AS (
    SELECT 
        pl.PostId,
        COUNT(DISTINCT pl.RelatedPostId) AS LinkedCount,
        AVG(lp.Score) AS AvgLinkedScore
    FROM 
        PostLinks pl
    JOIN 
        Posts lp ON lp.Id = pl.RelatedPostId
    WHERE 
        pl.LinkTypeId = 3
    GROUP BY 
        pl.PostId
)
SELECT 
    tq.TagName,
    COUNT(DISTINCT tq.PostId) AS QuestionCount,
    AVG(tq.QuestionScore) AS AvgQuestionScore,
    SUM(tq.ViewCount) AS TotalViews,
    AVG(tq.AnswerCount) AS AvgAnswers,
    SUM(tq.UpVotes) AS TotalUpVotes,
    SUM(tq.DownVotes) AS TotalDownVotes,
    AVG(tq.EditCount) AS AvgEdits,
    AVG(tq.CommentCountDetailed) AS AvgComments,
    ud.DisplayName AS TopAnswerer,
    ud.Reputation AS TopAnswererRep,
    tap.AnswerCount AS TopAnswerCount,
    tap.AvgAnswerScore AS TopAvgScore,
    ud.BadgeCount AS TopBadgeCount,
    ud.GoldBadges AS TopGoldBadges,
    AVG(lpa.LinkedCount) AS AvgLinkedDuplicates,
    AVG(lpa.AvgLinkedScore) AS AvgDuplicateScore,
    RANK() OVER (ORDER BY COUNT(DISTINCT tq.PostId) DESC) AS TagPopularityRank
FROM 
    TagQuestions tq
JOIN 
    TopAnswersPerTag tap ON tap.TagId = tq.TagId AND tap.UserRank = 1
JOIN 
    UserDetails ud ON ud.UserId = tap.OwnerUserId
LEFT JOIN 
    LinkedPostsAnalysis lpa ON lpa.PostId = tq.PostId
GROUP BY 
    tq.TagName, ud.DisplayName, ud.Reputation, tap.AnswerCount, tap.AvgAnswerScore, ud.BadgeCount, ud.GoldBadges
HAVING 
    COUNT(DISTINCT tq.PostId) > 100
ORDER BY 
    TagPopularityRank
LIMIT 50;