-- {"query": "4065.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1302} 

WITH RECURSIVE PostThread AS (
    -- Base case: Select top-level questions
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.ParentId,
        p.AcceptedAnswerId,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        p.Title,
        p.Tags,
        0 AS Depth,
        CAST(p.Id AS VARCHAR(MAX)) AS Path,
        p.OwnerUserId AS RootOwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.ParentId IS NULL

    UNION ALL

    -- Recursive step: Select answers and their replies
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.ParentId,
        p.AcceptedAnswerId,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        p.Title,
        p.Tags,
        pt.Depth + 1 AS Depth,
        pt.Path + '->' + CAST(p.Id AS VARCHAR(MAX)),
        pt.RootOwnerUserId
    FROM Posts p
    JOIN PostThread pt ON p.ParentId = pt.Id
    WHERE p.PostTypeId = 2 -- Answers
),
UserPostCounts AS (
    SELECT
        OwnerUserId,
        COUNT(Id) AS TotalPosts,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(CAST(Score AS FLOAT)) AS AvgScore
    FROM Posts
    WHERE OwnerUserId IS NOT NULL AND OwnerUserId <> -1
    GROUP BY OwnerUserId
),
UserBadgeCounts AS (
    SELECT
        UserId,
        COUNT(CASE WHEN Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges
    GROUP BY UserId
),
RecentPostActivity AS (
    SELECT
        PostId,
        COUNT(*) AS CommentActivityCount,
        MAX(CreationDate) AS LastCommentDate
    FROM Comments
    WHERE CreationDate >= DATEADD(day, -7, GETDATE())
    GROUP BY PostId
),
HighScoringAnswers AS (
    SELECT
        p.Id,
        p.ParentId AS QuestionId,
        p.OwnerUserId,
        p.Score,
        ROW_NUMBER() OVER(PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 2 AND p.Score > 5 -- High scoring answers
)
SELECT
    pt.Id AS PostId,
    pt.PostTypeId,
    pt.Depth,
    pt.Path,
    pt.Score AS PostScore,
    pt.AnswerCount AS QuestionAnswerCount,
    pt.Title AS QuestionTitle,
    pt.Tags AS QuestionTags,
    pt.CreationDate AS PostCreationDate,
    u.DisplayName AS PostOwnerDisplayName,
    COALESCE(upc.TotalPosts, 0) AS TotalUserPosts,
    COALESCE(upc.QuestionCount, 0) AS UserQuestionCount,
    COALESCE(upc.AnswerCount, 0) AS UserAnswerCount,
    COALESCE(upc.AvgScore, 0.0) AS UserAvgScore,
    COALESCE(ubc.GoldBadges, 0) AS UserGoldBadges,
    COALESCE(ubc.SilverBadges, 0) AS UserSilverBadges,
    COALESCE(ubc.BronzeBadges, 0) AS UserBronzeBadges,
    rpa.CommentActivityCount AS RecentCommentActivity,
    CASE WHEN pt.PostTypeId = 1 AND pt.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAcceptedAnswer,
    hsa.Score AS TopAnswerScore,
    hsa.OwnerUserId AS TopAnswerOwnerUserId,
    CASE WHEN pt.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
    DATEDIFF(day, pt.CreationDate, pt.ClosedDate) AS DaysToClose,
    LOWER(SUBSTRING(pt.Tags, 2, CHARINDEX('><', pt.Tags + '><') - 2)) AS PrimaryTag
FROM PostThread pt
LEFT JOIN Users u ON pt.OwnerUserId = u.Id
LEFT JOIN UserPostCounts upc ON pt.OwnerUserId = upc.OwnerUserId
LEFT JOIN UserBadgeCounts ubc ON pt.OwnerUserId = ubc.UserId
LEFT JOIN RecentPostActivity rpa ON pt.Id = rpa.PostId
LEFT JOIN HighScoringAnswers hsa ON pt.Id = hsa.QuestionId AND hsa.rn = 1
WHERE pt.Depth < 3 -- Limit thread depth for performance
  AND pt.PostCreationDate BETWEEN DATEADD(year, -1, GETDATE()) AND GETDATE()
  AND (pt.Score > 10 OR pt.AnswerCount > 5 OR ubc.GoldBadges > 2)
  AND pt.OwnerUserId IS NOT NULL
  AND pt.OwnerUserId <> -1
  AND COALESCE(u.Location, '') LIKE '%USA%'
  OR pt.Id IN (SELECT PostId FROM PostLinks WHERE LinkTypeId = 3) -- Posts that are duplicates
ORDER BY pt.Score DESC, pt.CreationDate DESC
OFFSET 0 ROWS FETCH NEXT 1000 ROWS ONLY;
