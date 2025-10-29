-- {"query": "1953.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2422} 

WITH UserEngagementSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS TotalQuestions,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalAnswers,
        COALESCE(COUNT(p.Id), 0) AS TotalPosts,
        COALESCE(AVG(p.Score), 0.0) AS AvgPostScore,
        COALESCE(SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL AND p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionsWithAcceptedAnswer,
        COALESCE(COUNT(c.Id), 0) AS TotalComments,
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadgesCount,
        COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadgesCount,
        COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadgesCount,
        COALESCE(MAX(ph.CreationDate), u.CreationDate) AS LastHistoryActivity
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c ON u.Id = c.UserId
    LEFT JOIN Badges AS b ON u.Id = b.UserId
    LEFT JOIN PostHistory AS ph ON u.Id = ph.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostActivityMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.LastActivityDate,
        p.LastEditDate,
        p.CommunityOwnedDate,
        p.ClosedDate,
        LENGTH(p.Body) AS BodyLength,
        LENGTH(p.Title) AS TitleLength,
        COALESCE(EXTRACT(EPOCH FROM (NOW() - p.CreationDate)) / 86400, 0) AS PostAgeDays,
        COALESCE(EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 86400, 0) AS DaysSinceCreationActivity,
        (SELECT MAX(ph2.CreationDate) FROM PostHistory ph2 WHERE ph2.PostId = p.Id AND ph2.PostHistoryTypeId IN (4,5,6)) AS LastRelevantEditDate,
        p.Tags,
        p.AcceptedAnswerId,
        p.ParentId,
        p.Body,
        p.Title
    FROM Posts AS p
),
PostCommentSummary AS (
    SELECT
        c.PostId,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LatestCommentDate,
        COUNT(c.Id) AS TotalCommentsOnPost,
        SUM(CASE WHEN c.Score >= 5 THEN 1 ELSE 0 END) AS HighScoreComments
    FROM Comments AS c
    GROUP BY c.PostId
),
PostPrimaryTag AS (
    SELECT
        p.Id AS PostId,
        TRIM(SUBSTRING(p.Tags FROM 2 FOR POSITION('><' IN p.Tags || '><') - 2)) AS PrimaryTagName
    FROM Posts AS p
    WHERE p.Tags IS NOT NULL
      AND LENGTH(p.Tags) > 2
      AND p.PostTypeId = 1
),
OverallTagMetrics AS (
    SELECT
        ppt.PrimaryTagName AS TagName,
        COUNT(DISTINCT ppt.PostId) AS TotalTaggedQuestions,
        AVG(p.Score) AS AvgQuestionScoreForTag,
        COUNT(DISTINCT p.OwnerUserId) AS UniqueUsersPerTag
    FROM PostPrimaryTag AS ppt
    INNER JOIN Posts AS p ON ppt.PostId = p.Id
    GROUP BY ppt.PrimaryTagName
),
HighlyEngagedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        'Question' AS PostType
    FROM Posts AS p
    WHERE p.PostTypeId = 1
      AND p.Score >= 100
      AND p.ViewCount >= 5000
      AND p.AnswerCount > 0
    UNION ALL
    SELECT
        p.Id AS PostId,
        p.Score,
        0 AS ViewCount,
        p.CreationDate,
        'Answer' AS PostType
    FROM Posts AS p
    WHERE p.PostTypeId = 2
      AND p.Score >= 50
      AND p.ParentId IS NOT NULL
)
SELECT
    ues.UserId,
    ues.DisplayName,
    ues.Reputation,
    ues.TotalQuestions,
    ues.TotalAnswers,
    ues.AvgPostScore,
    ues.GoldBadgesCount,
    pam.PostId,
    pam.PostTypeId,
    pam.PostCreationDate,
    pam.PostScore,
    pam.ViewCount,
    pam.AnswerCount,
    pam.PostAgeDays,
    pam.DaysSinceCreationActivity,
    pam.BodyLength,
    pam.TitleLength,
    pcs.TotalCommentsOnPost,
    pcs.AvgCommentScore,
    ppt.PrimaryTagName,
    otm.AvgQuestionScoreForTag,
    otm.UniqueUsersPerTag,
    (
        SELECT COALESCE(MAX(c_corr.Score), 0)
        FROM Comments AS c_corr
        WHERE c_corr.PostId = pam.PostId
    ) AS TopCommentScore,
    RANK() OVER (ORDER BY ues.Reputation DESC, ues.TotalPosts DESC) AS UserEngagementRank,
    NTILE(10) OVER (ORDER BY ues.Reputation DESC) AS ReputationDecile,
    AVG(pam.PostScore) OVER (PARTITION BY ues.UserId ORDER BY pam.PostCreationDate) AS RunningAvgUserPostScore,
    COALESCE(EXTRACT(EPOCH FROM (pam.PostCreationDate - LAG(pam.PostCreationDate, 1, pam.PostCreationDate) OVER (PARTITION BY ues.UserId ORDER BY pam.PostCreationDate))) / 86400, 0) AS DaysSincePrevPost,
    CASE
        WHEN pam.PostTypeId = 1 AND pam.AcceptedAnswerId IS NOT NULL AND pam.PostScore > 50 THEN 'High-Quality Solved Question'
        WHEN pam.PostTypeId = 1 AND pam.AcceptedAnswerId IS NULL AND pam.PostAgeDays > 30 AND COALESCE(pam.ViewCount, 0) > 1000 THEN 'Old Unanswered Popular Question'
        WHEN pam.PostTypeId = 2 AND pam.PostScore > 75 AND pam.OwnerUserId IS NOT NULL THEN 'Highly Rated Answer by Active User'
        WHEN pam.CommunityOwnedDate IS NOT NULL THEN 'Community Wiki Post'
        WHEN pam.ClosedDate IS NOT NULL THEN 'Closed Post'
        ELSE 'Regular Post'
    END AS PostCategory,
    UPPER(SUBSTRING(COALESCE(pam.Title, 'No Title') || ' - ' || SUBSTRING(COALESCE(pam.Body, ''), 1, 50), 1, 100)) AS PostSummarySnippet,
    COALESCE(pam.LastEditDate, pam.PostCreationDate) AS EffectiveLastModificationDate,
    pl.LinkTypeId,
    pl.RelatedPostId,
    CASE
        WHEN pl.LinkTypeId = 1 THEN 'Linked Post'
        WHEN pl.LinkTypeId = 3 THEN 'Duplicate Post'
        ELSE 'No Specific Link'
    END AS LinkDescription,
    CASE
        WHEN EXISTS (SELECT 1 FROM HighlyEngagedPosts hep WHERE hep.PostId = pam.PostId) THEN TRUE
        ELSE FALSE
    END AS IsHighlyEngaged,
    (pam.PostScore * 0.7 + COALESCE(pam.ViewCount, 0) * 0.1 + COALESCE(pam.CommentCount, 0) * 0.2) AS WeightedPostPopularityMetric,
    COALESCE(
        (SELECT p_target.Score FROM Posts p_target WHERE p_target.Id = pam.AcceptedAnswerId AND pam.PostTypeId = 1),
        (SELECT p_target.Score FROM Posts p_target WHERE p_target.Id = pam.ParentId AND pam.PostTypeId = 2),
        0
    ) AS ParentOrAcceptedScore,
    AVG(pam.PostScore) OVER (PARTITION BY pam.PostTypeId ORDER BY pam.PostCreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS MovingAvgPostScore
FROM UserEngagementSummary AS ues
INNER JOIN PostActivityMetrics AS pam ON ues.UserId = pam.OwnerUserId
LEFT JOIN PostCommentSummary AS pcs ON pam.PostId = pcs.PostId
LEFT JOIN PostPrimaryTag AS ppt ON pam.PostId = ppt.PostId
LEFT JOIN OverallTagMetrics AS otm ON ppt.PrimaryTagName = otm.TagName
LEFT JOIN PostLinks AS pl ON pam.PostId = pl.PostId
WHERE
    ues.Reputation > 1000
    AND pam.PostScore >= 5
    AND pam.PostCreationDate >= NOW() - INTERVAL '5 year'
    AND (pam.ClosedDate IS NULL OR pam.PostAgeDays < 365)
    AND pam.Body LIKE '%performance%'
    AND NOT EXISTS (
        SELECT 1
        FROM Votes v
        WHERE v.PostId = pam.PostId
          AND v.VoteTypeId = 3
          AND v.CreationDate > NOW() - INTERVAL '6 months'
    )
    AND ues.TotalQuestions >= 1
    AND (ppt.PrimaryTagName IS NULL OR otm.UniqueUsersPerTag > 10)
ORDER BY
    UserEngagementRank ASC,
    WeightedPostPopularityMetric DESC,
    pam.PostCreationDate DESC
LIMIT 1000;
