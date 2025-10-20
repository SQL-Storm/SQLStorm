-- {"query": "50054.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1308} 

WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        SUM(p.ViewCount) AS TotalViewCount,
        SUM(p.FavoriteCount) AS TotalFavoriteCount,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
        (
            SELECT COUNT(*)
            FROM Badges b
            WHERE b.UserId = u.Id AND b.Class = 1
        ) AS GoldBadges,
        (
            SELECT COUNT(*)
            FROM Comments c
            WHERE c.UserId = u.Id
        ) AS CommentCount
    FROM
        Users u
    JOIN
        Posts p ON u.Id = p.OwnerUserId
    WHERE
        u.Reputation > 10000 AND p.CommunityOwnedDate IS NULL AND p.ClosedDate IS NULL
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 50
),
UserTagPerformance AS (
    SELECT
        OwnerUserId,
        Tag,
        TagCount,
        AvgTagScore,
        TagRank
    FROM (
        SELECT
            a.OwnerUserId,
            t.Tag,
            COUNT(*) AS TagCount,
            AVG(a.Score) AS AvgTagScore,
            ROW_NUMBER() OVER (PARTITION BY a.OwnerUserId ORDER BY COUNT(*) DESC, AVG(a.Score) DESC) AS TagRank
        FROM
            Posts a
        JOIN
            Posts q ON a.ParentId = q.Id
        CROSS JOIN LATERAL
            unnest(string_to_array(substring(q.Tags, 2, length(q.Tags) - 2), '><')) AS t(Tag)
        WHERE
            a.PostTypeId = 2 -- Answers
            AND a.OwnerUserId IN (SELECT UserId FROM UserActivitySummary)
        GROUP BY
            a.OwnerUserId, t.Tag
    ) AS RankedTags
    WHERE TagRank <= 5
),
PostInteractionTimeline AS (
    SELECT
        p.OwnerUserId,
        p.Id AS PostId,
        p.CreationDate AS PostCreationDate,
        LAG(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostDate,
        LEAD(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostDate,
        (SELECT MIN(v.CreationDate) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS FirstUpvoteDate,
        (SELECT MIN(c.CreationDate) FROM Comments c WHERE c.PostId = p.Id) AS FirstCommentDate
    FROM
        Posts p
    WHERE
        p.PostTypeId IN (1, 2)
        AND p.OwnerUserId IN (SELECT UserId FROM UserActivitySummary)
),
FinalUserRanking AS (
    SELECT
        uas.UserId,
        uas.DisplayName,
        uas.Reputation,
        uas.QuestionCount,
        uas.AnswerCount,
        uas.TotalScore,
        uas.AvgAnswerScore,
        uas.GoldBadges,
        uas.CommentCount,
        AVG(EXTRACT(EPOCH FROM (pit.PostCreationDate - pit.PreviousPostDate))) AS AvgSecondsBetweenPosts,
        MAX(CASE WHEN utp.TagRank = 1 THEN utp.Tag END) AS TopTag,
        MAX(CASE WHEN utp.TagRank = 1 THEN utp.AvgTagScore END) AS TopTagAvgScore,
        MAX(CASE WHEN utp.TagRank = 2 THEN utp.Tag END) AS SecondTag,
        MAX(CASE WHEN utp.TagRank = 3 THEN utp.Tag END) AS ThirdTag
    FROM
        UserActivitySummary uas
    JOIN
        PostInteractionTimeline pit ON uas.UserId = pit.OwnerUserId
    LEFT JOIN
        UserTagPerformance utp ON uas.UserId = utp.OwnerUserId
    GROUP BY
        uas.UserId, uas.DisplayName, uas.Reputation, uas.QuestionCount, uas.AnswerCount, uas.TotalScore, uas.AvgAnswerScore, uas.GoldBadges, uas.CommentCount
)
SELECT
    DisplayName,
    Reputation,
    QuestionCount,
    AnswerCount,
    CAST(AvgAnswerScore AS DECIMAL(10, 2)) AS AvgAnswerScore,
    GoldBadges,
    CommentCount,
    CAST(AvgSecondsBetweenPosts / 3600 AS DECIMAL(10, 2)) AS AvgHoursBetweenPosts,
    TopTag,
    CAST(TopTagAvgScore AS DECIMAL(10, 2)) AS TopTagAvgScore,
    SecondTag,
    ThirdTag,
    DENSE_RANK() OVER (ORDER BY (Reputation * 0.5 + AvgAnswerScore * 50 * 0.3 + GoldBadges * 100 * 0.2) DESC) AS InfluenceRank
FROM
    FinalUserRanking
WHERE
    AvgSecondsBetweenPosts IS NOT NULL AND TopTag IS NOT NULL
ORDER BY
    InfluenceRank ASC, Reputation DESC
LIMIT 200;
