-- {"query": "19025.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2734} 

WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(P.ViewCount, 0)) AS TotalPostViews,
        COUNT(DISTINCT C.Id) AS TotalComments,
        MAX(P.LastActivityDate) AS LastPostActivity
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostEditActivity AS (
    SELECT
        PH.PostId,
        PH.UserId AS EditorUserId,
        COUNT(DISTINCT PH.RevisionGUID) AS EditCount,
        MAX(PH.CreationDate) AS LastEditDate,
        MIN(PH.CreationDate) AS FirstEditDate
    FROM PostHistory AS PH
    WHERE PH.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
    GROUP BY PH.PostId, PH.UserId
),
QuestionDetails AS (
    SELECT
        Q.Id AS QuestionId,
        Q.OwnerUserId,
        Q.CreationDate AS QuestionCreationDate,
        Q.Score AS QuestionScore,
        Q.ViewCount AS QuestionViewCount,
        Q.AnswerCount,
        Q.CommentCount AS QuestionCommentCount,
        Q.FavoriteCount,
        Q.Tags,
        Q.ClosedDate,
        Q.AcceptedAnswerId,
        (SELECT MAX(A.Score) FROM Posts AS A WHERE A.ParentId = Q.Id AND A.PostTypeId = 2) AS MaxAnswerScore, -- Correlated subquery for answer quality
        (SELECT COUNT(DISTINCT V.UserId) FROM Votes AS V WHERE V.PostId = Q.Id AND V.VoteTypeId = 5) AS TotalFavoritesLegacy, -- legacy favorite votes
        CASE
            WHEN Q.Tags LIKE '%<sql>%' OR Q.Tags LIKE '%<database>%' OR Q.Tags LIKE '%<performance>%' THEN TRUE
            ELSE FALSE
        END AS IsDatabaseOrPerfRelated,
        COALESCE(Q.FavoriteCount, 0) * 10 + Q.Score * 5 + Q.ViewCount * 0.1 + Q.CommentCount * 2 AS QuestionEngagementScore
    FROM Posts AS Q
    WHERE Q.PostTypeId = 1
),
UserRankedActivity AS (
    SELECT
        UE.UserId,
        UE.DisplayName,
        UE.Reputation,
        UE.UserCreationDate,
        UE.LastAccessDate,
        UE.TotalPosts,
        UE.QuestionCount,
        UE.AnswerCount,
        UE.TotalPostScore,
        UE.TotalPostViews,
        UE.TotalComments,
        UE.LastPostActivity,
        SUM(COALESCE(PEA.EditCount, 0)) AS TotalSelfEdits,
        NTILE(10) OVER (ORDER BY UE.Reputation DESC, UE.TotalPostScore DESC) AS ReputationDecile, -- Window function: NTILE
        RANK() OVER (PARTITION BY EXTRACT(YEAR FROM UE.CreationDate) ORDER BY UE.Reputation DESC) AS RankByReputationInYear -- Window function: RANK
    FROM UserEngagement AS UE
    LEFT JOIN PostEditActivity AS PEA ON UE.UserId = PEA.EditorUserId AND PEA.PostId IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = UE.UserId) -- Correlated subquery in join condition
    GROUP BY
        UE.UserId, UE.DisplayName, UE.Reputation, UE.UserCreationDate, UE.LastAccessDate,
        UE.TotalPosts, UE.QuestionCount, UE.AnswerCount, UE.TotalPostScore, UE.TotalPostViews,
        UE.TotalComments, UE.LastPostActivity
),
BadgeSummary AS (
    SELECT
        B.UserId,
        COUNT(CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN B.Id END) AS BronzeBadges,
        MAX(B.Date) AS LastBadgeDate
    FROM Badges AS B
    GROUP BY B.UserId
),
TopTagsSummary AS (
    SELECT
        T.TagName,
        COUNT(DISTINCT Q.QuestionId) AS QuestionCountWithTag,
        SUM(Q.QuestionScore) AS TotalScoreWithTag,
        AVG(Q.QuestionCommentCount) AS AvgCommentCountWithTag,
        SUM(CASE WHEN Q.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedQuestionCountWithTag
    FROM QuestionDetails AS Q
    JOIN Tags AS T ON Q.Tags LIKE '%' || '<' || T.TagName || '>' || '%'
    GROUP BY T.TagName
    HAVING COUNT(DISTINCT Q.QuestionId) > 50 -- Filter for sufficiently used tags
),
DiverseUserContributions AS ( -- Set operator: UNION ALL to combine different user contribution profiles
    -- Users actively asking about specific topics
    SELECT
        U.Id AS UserId,
        'ActiveQuestioner' AS ContributionRole,
        SUM(QD.QuestionEngagementScore) AS TotalEngagementScore,
        COUNT(QD.QuestionId) AS ContributionCount
    FROM Users AS U
    JOIN QuestionDetails AS QD ON U.Id = QD.OwnerUserId
    WHERE QD.IsDatabaseOrPerfRelated
    GROUP BY U.Id
    HAVING COUNT(QD.QuestionId) > 3 AND SUM(QD.QuestionEngagementScore) > 100
    UNION ALL
    -- Users providing high-score answers or heavily editing posts
    SELECT
        U.Id AS UserId,
        'HighImpactContributor' AS ContributionRole,
        SUM(COALESCE(P.Score, 0)) + SUM(COALESCE(PEA.EditCount, 0) * 10) AS TotalEngagementScore, -- Weighted score
        COUNT(P.Id) + SUM(COALESCE(PEA.EditCount, 0)) AS ContributionCount
    FROM Users AS U
    JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN PostEditActivity AS PEA ON P.Id = PEA.PostId AND U.Id = PEA.EditorUserId
    WHERE P.PostTypeId = 2 AND P.Score > 20 -- High scoring answers
    GROUP BY U.Id
    HAVING COUNT(P.Id) > 5 OR SUM(COALESCE(PEA.EditCount, 0)) > 10
)
SELECT
    URA.UserId,
    URA.DisplayName,
    URA.Reputation,
    URA.UserCreationDate,
    URA.LastAccessDate,
    URA.TotalPosts,
    URA.QuestionCount,
    URA.AnswerCount,
    URA.TotalSelfEdits,
    URA.ReputationDecile,
    URA.RankByReputationInYear,
    BS.GoldBadges,
    BS.SilverBadges,
    BS.BronzeBadges,
    BS.LastBadgeDate,
    DUR.ContributionRole, -- From UNION ALL CTE
    DUR.TotalEngagementScore AS DiverseContributionEngagement,
    SUM(QD.QuestionEngagementScore) AS TotalQuestionEngagement,
    AVG(QD.QuestionEngagementScore) AS AvgQuestionEngagement,
    SUM(CASE WHEN QD.IsDatabaseOrPerfRelated THEN 1 ELSE 0 END) AS DatabasePerfQuestions,
    SUM(CASE WHEN QD.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedQuestionsOwned,
    COUNT(DISTINCT CASE WHEN PL.LinkTypeId = 3 THEN PL.RelatedPostId ELSE NULL END) AS DuplicatedQuestionsLinked,
    COALESCE(NULLIF(URA.TotalComments, 0), 1) AS TotalCommentsAdjustedForDivision, -- NULL logic, complicated calc
    CAST(SUM(CASE WHEN QD.IsDatabaseOrPerfRelated THEN 1 ELSE 0 END) AS REAL) / COALESCE(NULLIF(URA.QuestionCount, 0), 1) AS DatabasePerfRatio,
    STRING_AGG(DISTINCT TTS.TagName, ', ') FILTER (WHERE TTS.TotalScoreWithTag > 1000) AS TopScoringTagsContributed, -- String aggregation, complex filter
    CASE
        WHEN URA.Reputation > 75000 AND BS.GoldBadges >= 10 AND DUR.ContributionRole IS NOT NULL THEN 'StackOverflow Legend'
        WHEN URA.Reputation > 25000 AND (BS.GoldBadges >= 3 OR URA.TotalSelfEdits > 50) AND DUR.ContributionRole = 'HighImpactContributor' THEN 'Domain Expert'
        WHEN URA.Reputation > 5000 AND URA.TotalPosts > 100 AND URA.QuestionCount > 10 AND URA.AnswerCount > 20 THEN 'Prolific Contributor'
        WHEN URA.Reputation > 1000 AND URA.TotalComments > 50 THEN 'Community Engager'
        ELSE 'Active Participant'
    END AS UserCategory, -- Complicated CASE expression
    (SELECT COUNT(DISTINCT V.PostId) FROM Votes AS V WHERE V.UserId = URA.UserId AND V.VoteTypeId = 2 AND V.CreationDate >= URA.LastAccessDate - INTERVAL '30 days') AS RecentUpvotesGiven -- Correlated subquery for recent activity
FROM UserRankedActivity AS URA
LEFT JOIN BadgeSummary AS BS ON URA.UserId = BS.UserId
LEFT JOIN QuestionDetails AS QD ON URA.UserId = QD.OwnerUserId
LEFT JOIN PostLinks AS PL ON QD.QuestionId = PL.PostId -- Outer Join
LEFT JOIN TopTagsSummary AS TTS ON QD.Tags LIKE '%' || '<' || TTS.TagName || '>' || '%'
LEFT JOIN DiverseUserContributions AS DUR ON URA.UserId = DUR.UserId -- Joining the UNION ALL CTE
WHERE
    URA.Reputation > 1000
    AND URA.LastAccessDate > URA.UserCreationDate + INTERVAL '180 days' -- Active users for at least 6 months
    AND URA.TotalPosts > 20
    AND (URA.TotalSelfEdits > 10 OR URA.TotalComments > 30 OR DUR.UserId IS NOT NULL) -- Complex predicate involving UNION ALL CTE
GROUP BY
    URA.UserId, URA.DisplayName, URA.Reputation, URA.UserCreationDate, URA.LastAccessDate,
    URA.TotalPosts, URA.QuestionCount, URA.AnswerCount, URA.TotalSelfEdits,
    URA.ReputationDecile, URA.RankByReputationInYear,
    BS.GoldBadges, BS.SilverBadges, BS.BronzeBadges, BS.LastBadgeDate,
    DUR.ContributionRole, DUR.TotalEngagementScore
HAVING
    SUM(COALESCE(QD.QuestionEngagementScore, 0)) + COALESCE(DUR.TotalEngagementScore, 0) > 500
    AND (COUNT(DISTINCT CASE WHEN PL.LinkTypeId = 3 THEN PL.RelatedPostId ELSE NULL END) > 0 OR SUM(QD.QuestionCommentCount) > 75 OR COUNT(DISTINCT TTS.TagName) > 3)
ORDER BY
    URA.Reputation DESC, TotalQuestionEngagement DESC, DiverseContributionEngagement DESC
LIMIT 100;
