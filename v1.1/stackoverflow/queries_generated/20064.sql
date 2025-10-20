-- {"query": "20064.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1283} 

WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1, 2)) AS AvgPostScore,
        MAX(p.LastActivityDate) AS LastPostActivityDate
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    WHERE
        u.Id > 0
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PowerUsers AS (
    SELECT
        UserId,
        DisplayName,
        Reputation,
        'Veteran Power User' AS UserCategory
    FROM
        UserActivitySummary
    WHERE
        Reputation > 50000
        AND TotalPosts > 100
        AND GoldBadges > 5
        AND UserCreationDate < (now() - interval '8 year')
        AND AvgPostScore > 10
),
RisingStars AS (
    SELECT
        UserId,
        DisplayName,
        Reputation,
        'Rising Star' AS UserCategory
    FROM
        UserActivitySummary
    WHERE
        Reputation > 10000
        AND UserCreationDate >= (now() - interval '3 year')
        AND (GoldBadges > 0 OR SilverBadges > 20)
        AND CommentCount > 50
),
CombinedUsers AS (
    SELECT UserId, DisplayName, Reputation, UserCategory FROM PowerUsers
    UNION ALL
    SELECT UserId, DisplayName, Reputation, UserCategory FROM RisingStars
),
RankedUserPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.Tags,
        p.AnswerCount,
        p.AcceptedAnswerId,
        p.LastEditorUserId,
        cu.UserCategory,
        cu.DisplayName,
        cu.Reputation,
        LAG(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostDate,
        DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRankByUser,
        SUM(p.Score) OVER (PARTITION BY p.OwnerUserId) AS TotalScoreOfAllPosts
    FROM
        Posts p
    JOIN
        CombinedUsers cu ON p.OwnerUserId = cu.UserId
    WHERE
        p.PostTypeId = 1 -- Only consider questions
)
SELECT
    rup.DisplayName,
    rup.UserCategory,
    rup.Reputation,
    rup.PostId,
    rup.Title,
    rup.Score AS PostScore,
    rup.ViewCount,
    rup.PostRankByUser,
    rup.TotalScoreOfAllPosts,
    rup.CreationDate AS PostCreationDate,
    COALESCE(aa.Score, -1) AS AcceptedAnswerScore,
    le.DisplayName AS LastEditorDisplayName,
    CASE
        WHEN rup.Score > 0 THEN CAST(rup.ViewCount AS numeric) / rup.Score
        ELSE NULL
    END AS ViewToScoreRatio,
    EXTRACT(EPOCH FROM (rup.CreationDate - rup.PreviousPostDate)) / 3600 AS HoursSinceLastPost,
    substring(rup.Tags from '<([^>]+)>') AS FirstTag,
    (SELECT COUNT(*)
     FROM PostLinks pl
     WHERE pl.RelatedPostId = rup.PostId AND pl.LinkTypeId = 3) AS TimesMarkedAsDuplicate,
    CASE
        WHEN rup.Score > 100 AND COALESCE(rup.FavoriteCount, 0) > 20 AND rup.AnswerCount > 5 THEN 'Highly Engaging'
        WHEN rup.Score > 20 OR COALESCE(rup.FavoriteCount, 0) > 5 THEN 'Engaging'
        WHEN rup.Score <= 0 THEN 'Low Engagement'
        ELSE 'Standard'
    END AS EngagementCategory,
    length(rup.Body) AS BodyLength,
    POSITION('performance' IN lower(rup.Body)) > 0 AS MentionsPerformance
FROM
    RankedUserPosts rup
LEFT JOIN
    Posts aa ON rup.AcceptedAnswerId = aa.Id
LEFT JOIN
    Users le ON rup.LastEditorUserId = le.Id
WHERE
    rup.PostRankByUser <= 10
    AND rup.Title IS NOT NULL
    AND rup.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1 AND CreationDate > now() - interval '1 year')
ORDER BY
    rup.DisplayName,
    rup.PostRankByUser;
