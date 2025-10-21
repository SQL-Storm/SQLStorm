-- {"query": "28074.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1464} 

WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserJoinDate,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        AVG(p.Score) OVER (PARTITION BY u.Id) AS AvgPostScore,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    GROUP BY u.Id, u.Reputation, u.CreationDate, p.Score
),
PostDetails AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.ClosedDate,
        p.Tags,
        p.ViewCount,
        COALESCE(p.AnswerCount, 0) AS Answers,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC) AS ViewRank,
        LAG(p.Title, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevPostTitle,
        (SELECT MAX(CreationDate) FROM Votes WHERE PostId = p.Id AND VoteTypeId = 2) AS LastUpvoteDate
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL
),
UserComments AS (
    SELECT 
        UserId,
        PostId,
        STRING_AGG(SUBSTRING(c.Text FROM 1 FOR 50), '; ') AS CommentPreview,
        COUNT(*) OVER (PARTITION BY UserId) AS TotalComments
    FROM Comments c
    WHERE UserId IS NOT NULL
    GROUP BY UserId, PostId
)
SELECT 
    us.UserId,
    us.Reputation,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    pd.PostId,
    pd.Title,
    pd.ViewCount,
    pd.Answers,
    pd.ViewRank,
    uc.CommentPreview,
    uc.TotalComments,
    (SELECT COUNT(*) FROM PostLinks WHERE PostId = pd.PostId AND LinkTypeId = 3) AS DuplicateLinks,
    COALESCE(u.WebsiteUrl, 'No Website') AS Website,
    CASE 
        WHEN u.Location LIKE '%USA%' THEN 'US'
        WHEN u.Location IS NULL THEN 'Unknown'
        ELSE 'Non-US'
    END AS LocationCategory,
    DATE_PART('year', AGE(pd.CreationDate, us.UserJoinDate)) AS YearsSinceJoin,
    (SELECT STRING_AGG(TagName, ', ') FROM Tags WHERE Id = ANY(string_to_array(substring(pd.Tags, 2, length(pd.Tags)-2), '><'), '')::int[]) AS TagNames
FROM UserStats us
LEFT JOIN PostDetails pd ON us.UserId = pd.OwnerUserId AND pd.ViewRank <= 3
LEFT JOIN UserComments uc ON us.UserId = uc.UserId AND pd.PostId = uc.PostId
LEFT JOIN Users u ON us.UserId = u.Id
WHERE us.Reputation > 1000
    AND (pd.ViewCount > 1000 OR pd.ViewCount IS NULL)
    AND (us.GoldBadges > 0 OR us.SilverBadges > 5)
HAVING MAX(pd.Answers) OVER (PARTITION BY us.UserId) > 1 OR MAX(uc.TotalComments) OVER (PARTITION BY us.UserId) > 10
ORDER BY us.ReputationRank, pd.ViewRank;
