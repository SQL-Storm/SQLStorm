-- {"query": "1152.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2784} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsPosted,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersPosted,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswer
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id
),
PostDetailStats AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        COALESCE(p.ViewCount, 0) AS ViewCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
        p.LastActivityDate,
        p.ClosedDate,
        p.Title,
        p.Tags,
        COALESCE(SUM(c.Score), 0) AS TotalCommentScore,
        COUNT(DISTINCT c.Id) AS CommentCount,
        (SELECT MAX(pa.Score) FROM Posts pa WHERE pa.Id = p.AcceptedAnswerId) AS AcceptedAnswerScore, -- Correlated Subquery 1
        CASE
            WHEN p.PostTypeId = 1 AND COALESCE(p.ViewCount, 0) > 0
            THEN (COALESCE(p.AnswerCount, 0) * 1.5 + COALESCE(p.FavoriteCount, 0) * 2.0 + COUNT(DISTINCT c.Id) * 0.5) / COALESCE(p.ViewCount, 1.0)
            ELSE 0.0
        END AS QuestionEngagementRatio,
        LENGTH(p.Body) - LENGTH(REPLACE(p.Body, '<code>', '')) AS CodeBlockCount -- String calculation: count code blocks
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount,
        p.AnswerCount, p.FavoriteCount, p.LastActivityDate, p.ClosedDate, p.Title, p.Tags, p.Body
),
PostHistorySummary AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE NULL END) AS EditCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE NULL END) AS CloseEventCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE NULL END) AS ReopenEventCount,
        MAX(ph.CreationDate) AS LastHistoryEventDate
    FROM PostHistory ph
    GROUP BY ph.PostId
),
TagAnalysis AS (
    SELECT
        TRIM(UNNEST(STRING_TO_ARRAY(SUBSTRING(pds.Tags, 2, LENGTH(pds.Tags) - 2), '><'))) AS TagName,
        SUM(pds.Score) AS TagTotalScore,
        SUM(pds.ViewCount) AS TagTotalViewCount,
        COUNT(pds.PostId) AS TagPostCount,
        AVG(pds.QuestionEngagementRatio) AS AvgTagEngagementRatio
    FROM PostDetailStats pds
    WHERE pds.Tags IS NOT NULL AND pds.Tags != '' AND pds.PostTypeId = 1
    GROUP BY TagName
),
UserBadgeStats AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
HighImpactPosts AS ( -- Set operator: UNION ALL
    -- Questions with high engagement and views
    SELECT
        pds.PostId,
        pds.OwnerUserId,
        'HighEngagementQuestion' AS ImpactCategory,
        pds.Score AS BaseScore,
        (pds.QuestionEngagementRatio * 1000 + pds.ViewCount / 100) AS CalculatedImpact
    FROM PostDetailStats pds
    WHERE pds.PostTypeId = 1
      AND pds.QuestionEngagementRatio > 0.5
      AND pds.ViewCount > 5000
      AND pds.ClosedDate IS NULL
    UNION ALL
    -- Answers with very high score
    SELECT
        pds.PostId,
        pds.OwnerUserId,
        'VeryHighScoringAnswer' AS ImpactCategory,
        pds.Score AS BaseScore,
        (pds.Score * 5) AS CalculatedImpact
    FROM PostDetailStats pds
    WHERE pds.PostTypeId = 2
      AND pds.Score > 200
),
UserCloseReasonAnalysis AS (
    SELECT
        ucra.UserId,
        ucra.CloseReasonName,
        ucra.CloseCountForReason
    FROM (
        SELECT
            p.OwnerUserId AS UserId,
            cr.Name AS CloseReasonName,
            COUNT(ph.PostId) AS CloseCountForReason,
            ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY COUNT(ph.PostId) DESC, cr.Name) as rn
        FROM PostHistory ph
        JOIN Posts p ON ph.PostId = p.Id
        JOIN CloseReasonTypes cr ON ph.Comment ~ '^[0-9]+$' AND ph.Comment::smallint = cr.Id -- Ensure Comment is numeric for casting
        WHERE ph.PostHistoryTypeId = 10
          AND p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId, cr.Name
    ) ucra
    WHERE ucra.rn = 1
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    ua.TotalPosts,
    ua.QuestionsPosted,
    ua.AnswersPosted,
    ua.TotalPostScore,
    ub.TotalBadges,
    ub.GoldBadges,
    ub.SilverBadges,
    (ub.GoldBadges * 100 + ub.SilverBadges * 10 + ub.BronzeBadges) AS BadgeWeightScore,
    AVG(pds.Score) AS AveragePostScorePerUser,
    COUNT(DISTINCT pds.PostId) AS ActivePosts,
    SUM(CASE WHEN pds.PostTypeId = 1 AND pds.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedQuestionsCount,
    -- Window Function: Rank users by their total post score combined with reputation
    RANK() OVER (ORDER BY (ua.TotalPostScore + u.Reputation * 0.1) DESC, u.CreationDate ASC) AS UserOverallRank,
    -- Complex calculation based on various factors and a correlated subquery
    (u.Reputation * 0.5 + ua.TotalPostScore * 0.2 + ub.GoldBadges * 50 + ub.SilverBadges * 10 + ua.QuestionsWithAcceptedAnswer * 5 +
     (SELECT COALESCE(AVG(t_inner.AvgTagEngagementRatio), 0) -- Correlated Subquery 2: Avg engagement for user's primary tags
      FROM TagAnalysis t_inner
      WHERE t_inner.TagName IN (
          SELECT TRIM(UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')))
          FROM Posts p
          WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.Tags != ''
          ORDER BY p.Score DESC
          LIMIT 5 -- Consider only the top 5 highest-scoring questions' tags for the user
      )
     ) * 100
    ) AS CalculatedUserInfluenceScore,
    (SELECT COUNT(DISTINCT v.PostId) -- Correlated Subquery 3: Recent favorite votes by user
     FROM Votes v
     WHERE v.UserId = u.Id AND v.VoteTypeId = 5 -- Favorite votes
     AND v.CreationDate > u.LastAccessDate - INTERVAL '1 year'
    ) AS RecentFavoritesGiven,
    COUNT(CASE WHEN pds.LastActivityDate > CURRENT_DATE - INTERVAL '30 days' THEN 1 ELSE NULL END) AS RecentActivePostsCount,
    STRING_AGG(DISTINCT SUBSTRING(pds.Title, 1, 30) || '...', ' | ') WITHIN GROUP (ORDER BY pds.Score DESC) AS TopPostTitlesSample, -- String aggregation
    COALESCE(SUM(phs.EditCount), 0) AS TotalEditsAcrossPosts,
    COALESCE(SUM(CASE WHEN hip.ImpactCategory = 'HighEngagementQuestion' THEN 1 ELSE 0 END), 0) AS HighEngagementQuestionsContributed,
    COALESCE(SUM(CASE WHEN hip.ImpactCategory = 'VeryHighScoringAnswer' THEN 1 ELSE 0 END), 0) AS VeryHighScoringAnswersContributed,
    ucra.CloseReasonName AS MostFrequentCloseReasonByAuthor, -- Most frequent close reason for author's posts
    COALESCE(SUM(pds.CodeBlockCount), 0) AS TotalCodeBlockCount, -- Sum of code blocks in user's posts
    (SELECT COALESCE(MAX(ph_sum.EditCount), 0) FROM PostHistorySummary ph_sum JOIN Posts p_ph ON ph_sum.PostId = p_ph.Id WHERE p_ph.OwnerUserId = u.Id) AS MaxEditsOnSinglePostByUser -- Correlated Subquery 4
FROM Users u
LEFT JOIN UserActivity ua ON u.Id = ua.UserId
LEFT JOIN UserBadgeStats ub ON u.Id = ub.UserId
LEFT JOIN PostDetailStats pds ON u.Id = pds.OwnerUserId
LEFT JOIN PostHistorySummary phs ON pds.PostId = phs.PostId
LEFT JOIN HighImpactPosts hip ON pds.PostId = hip.PostId AND u.Id = hip.OwnerUserId
LEFT JOIN UserCloseReasonAnalysis ucra ON u.Id = ucra.UserId
WHERE u.Reputation > 5000 -- Filter for more established users
  AND u.LastAccessDate > CURRENT_DATE - INTERVAL '3 months' -- Recently active users
  AND (u.Location IS NOT NULL OR u.AboutMe IS NOT NULL OR u.WebsiteUrl IS NOT NULL) -- Users with some profile info
  AND (u.DisplayName LIKE 'A%' OR u.DisplayName LIKE 'S%' OR u.DisplayName LIKE 'D%') -- Diverse DisplayName filter
  AND u.Views > 500 -- Users with significant profile views
GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
    ua.TotalPosts, ua.QuestionsPosted, ua.AnswersPosted, ua.TotalPostScore,
    ub.TotalBadges, ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, ucra.CloseReasonName
HAVING
    COUNT(DISTINCT pds.PostId) > 10 -- Users with at least 10 posts
    AND SUM(pds.Score) > 200 -- And total post score over 200
    AND COALESCE(SUM(phs.EditCount), 0) > 5 -- At least 5 total edits
ORDER BY
    CalculatedUserInfluenceScore DESC, UserOverallRank ASC
LIMIT 200;
