-- {"query": "4328.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1135} 

WITH PostStats AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        pt.Name AS PostTypeName,
        CASE WHEN p.Tags IS NOT NULL THEN LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '><', '')) + 1 ELSE 0 END AS TagCount,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId != -1
),
UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.DisplayName AS UserName,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount,
        (SELECT SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) FROM Votes v WHERE v.UserId = u.Id) AS TotalUpVotes,
        (SELECT SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) FROM Votes v WHERE v.UserId = u.Id) AS TotalDownVotes,
        u.UpVotes AS UserUpVotesGiven,
        u.DownVotes AS UserDownVotesGiven,
        COALESCE(u.WebsiteUrl, 'No Website') AS WebsiteInfo
    FROM Users u
),
PostInteraction AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        SUM(c.Score) AS TotalCommentScore
    FROM Comments c
    GROUP BY c.PostId
),
ComplexPostData AS (
    SELECT
        ps.PostId,
        ps.PostTypeName,
        ue.UserName,
        ue.Reputation,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        COALESCE(pi.CommentCount, 0) AS ActualCommentCount,
        ps.FavoriteCount,
        ps.TagCount,
        DATEDIFF(DAY, ps.CreationDate, GETDATE()) AS DaysSinceCreation,
        CASE
            WHEN ps.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN ps.ViewCount > 10000 THEN 'High Traffic'
            WHEN ps.Score > 50 THEN 'High Score'
            ELSE 'Standard'
        END AS PostStatusCategory,
        CASE
            WHEN ps.PostTypeId = 1 THEN SUBSTRING(ps.Title, 1, 50)
            ELSE SUBSTRING(ps.Body, 1, 50)
        END AS Snippet,
        ue.BadgeCount,
        ue.TotalUpVotes,
        ue.TotalDownVotes,
        ue.UserUpVotesGiven,
        ue.UserDownVotesGiven,
        ue.WebsiteInfo,
        ps.rn
    FROM PostStats ps
    LEFT JOIN UserEngagement ue ON ps.OwnerUserId = ue.UserId
    LEFT JOIN PostInteraction pi ON ps.PostId = pi.PostId
)
SELECT
    cpd.PostId,
    cpd.PostTypeName,
    cpd.UserName,
    cpd.Reputation,
    cpd.Score,
    cpd.ViewCount,
    cpd.AnswerCount,
    cpd.ActualCommentCount,
    cpd.FavoriteCount,
    cpd.TagCount,
    cpd.DaysSinceCreation,
    cpd.PostStatusCategory,
    cpd.Snippet,
    cpd.BadgeCount,
    cpd.TotalUpVotes,
    cpd.TotalDownVotes,
    cpd.UserUpVotesGiven,
    cpd.UserDownVotesGiven,
    cpd.WebsiteInfo,
    CASE
        WHEN cpd.rn <= 10 THEN 'Top 10 Recent'
        WHEN cpd.rn BETWEEN 11 AND 50 THEN 'Next 40 Recent'
        ELSE 'Older Posts'
    END AS RecentCategory,
    LAG(cpd.Score, 1, 0) OVER (ORDER BY cpd.CreationDate) AS PreviousPostScore,
    SUM(cpd.ViewCount) OVER (ORDER BY cpd.CreationDate ROWS BETWEEN 9 PRECEDING AND CURRENT ROW) AS Rolling10DayViewCount,
    ROW_NUMBER() OVER (PARTITION BY cpd.PostTypeName ORDER BY cpd.Score DESC) AS RankByType
FROM ComplexPostData cpd
WHERE cpd.PostTypeName IN ('Question', 'Answer') AND cpd.Reputation > 100 AND cpd.DaysSinceCreation > 7
ORDER BY cpd.DaysSinceCreation, cpd.Score DESC;
