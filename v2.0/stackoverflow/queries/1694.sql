-- {"query": "1694.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3090}
WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(P.Score) AS TotalPostScore,
        MAX(P.CreationDate) AS LatestPostDate,
        AVG(CASE WHEN P.PostTypeId = 1 THEN P.ViewCount ELSE NULL END) AS AvgQuestionViewCount,
        SUM(COALESCE(P.FavoriteCount, 0)) AS TotalFavoriteCount,
        (SELECT STRING_AGG(tag, ', ')
         FROM (
            SELECT DISTINCT tag
            FROM (
              SELECT unnest(string_to_array(substring(P2.Tags, 2, length(P2.Tags)-2), '><')) AS tag
              FROM Posts P2
              WHERE P2.OwnerUserId = U.Id AND P2.Tags IS NOT NULL AND P2.PostTypeId IN (1,4,5)
            ) t1
            ORDER BY tag
         ) t2
        ) AS TopTagsInPosts,
        (SELECT AVG(COALESCE(C.Score, 0)) FROM Comments C WHERE C.UserId = U.Id AND C.CreationDate > U.CreationDate) AS AvgCommentScorePerUserPost
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    WHERE U.LastAccessDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months')
      AND U.Reputation > 500
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
    HAVING COUNT(P.Id) > 10 AND SUM(P.Score) > 100
),
PostEditHistoryDetails AS (
    SELECT
        PH.UserId,
        PH.PostId,
        PH.PostHistoryTypeId,
        PH.CreationDate AS EditDate,
        COALESCE(PH.Comment, 'No_Comment') AS EditComment,
        LENGTH(COALESCE(PH.Text, '')) AS EditedTextLength,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate DESC) AS LastEditRank,
        COUNT(PH.Id) OVER (
            PARTITION BY PH.UserId
            ORDER BY PH.CreationDate
            RANGE BETWEEN INTERVAL '90 days' PRECEDING AND CURRENT ROW
        ) AS RollingEditCount
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (4, 5, 6, 10, 11, 12, 13)
      AND PH.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
),
RankedPostsAndAnswers AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.Title,
        P.Tags,
        P.ParentId,
        P.AcceptedAnswerId,
        P.ClosedDate,
        COALESCE(P.LastEditorDisplayName, 'Unknown Editor') AS LastEditorDisplayName,
        RANK() OVER (PARTITION BY P.OwnerUserId, P.PostTypeId ORDER BY P.Score DESC, P.CreationDate DESC) AS PostRankByUserAndType,
        AVG(P.Score) OVER (PARTITION BY P.OwnerUserId, DATE_TRUNC('day', P.CreationDate) ORDER BY P.CreationDate) AS DailyAvgUserScore
    FROM Posts P
    WHERE P.OwnerUserId IS NOT NULL
      AND P.PostTypeId IN (1, 2)
      AND P.Score >= 1
),
BadgeAchievementSummary AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.TagBased = TRUE THEN 1 ELSE 0 END) AS TagBasedBadges,
        MAX(B.Date) AS LatestBadgeDate,
        (SELECT Name FROM Badges WHERE UserId = B.UserId AND Class = 1 ORDER BY Date DESC LIMIT 1) AS LatestGoldBadgeName
    FROM Badges B
    GROUP BY B.UserId
),
QuestionAnswerInteractions AS (
    SELECT
        Q.PostId AS QuestionId,
        Q.OwnerUserId AS QuestionOwnerId,
        Q.PostCreationDate AS QuestionDate,
        Q.Score AS QuestionScore,
        Q.Title AS QuestionTitle,
        Q.Tags AS QuestionTags,
        A.PostId AS AnswerId,
        A.OwnerUserId AS AnswerOwnerId,
        A.PostCreationDate AS AnswerDate,
        A.Score AS AnswerScore,
        A.PostRankByUserAndType AS AnswerRankByUser,
        CASE
            WHEN Q.AcceptedAnswerId IS NOT NULL AND Q.AcceptedAnswerId = A.PostId THEN 'Accepted'
            WHEN Q.AcceptedAnswerId IS NOT NULL AND Q.AcceptedAnswerId <> A.PostId THEN 'Other_Answer_Accepted'
            WHEN Q.AcceptedAnswerId IS NULL AND Q.AnswerCount > 0 THEN 'No_Accepted_But_Has_Answers'
            ELSE 'No_Answer_Accepted'
        END AS AnswerAcceptanceStatus,
        (LOWER(Q.Title) LIKE '%performance%' OR LOWER(Q.Title) LIKE '%benchmark%') AS IsPerformanceBenchmarkingQuestion,
        (SELECT COUNT(V.Id) FROM Votes V JOIN Users U2 ON V.UserId = U2.Id WHERE V.PostId = Q.PostId AND U2.Reputation > 1000) AS HighRepUserVotesOnQuestion
    FROM RankedPostsAndAnswers Q
    INNER JOIN RankedPostsAndAnswers A ON Q.PostId = A.ParentId AND Q.PostTypeId = 1 AND A.PostTypeId = 2
    WHERE Q.OwnerUserId <> A.OwnerUserId
      AND Q.Score >= 20 AND A.Score >= 15
),
PostLinkAggregates AS (
    SELECT
        PL.PostId,
        STRING_AGG(DISTINCT LT.Name, ', ') AS RelatedLinkTypes,
        COUNT(DISTINCT PL.RelatedPostId) AS TotalRelatedPosts,
        SUM(CASE WHEN LT.Name = 'Duplicate' THEN 1 ELSE 0 END) AS DuplicateLinkCount,
        MAX(CASE WHEN EXISTS (
            SELECT 1 FROM Posts RelP WHERE RelP.Id = PL.RelatedPostId AND RelP.Score > 100 AND RelP.PostTypeId = 1
        ) THEN 1 ELSE 0 END) = 1 AS HasHighScoreRelatedQuestion
    FROM PostLinks PL
    JOIN LinkTypes LT ON PL.LinkTypeId = LT.Id
    GROUP BY PL.PostId
)
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.LastAccessDate,
    UAS.TotalPosts,
    UAS.QuestionCount,
    UAS.AnswerCount,
    UAS.TotalPostScore,
    UAS.TopTagsInPosts,
    UAS.AvgCommentScorePerUserPost,
    BSA.TotalBadges,
    BSA.GoldBadges,
    BSA.LatestGoldBadgeName,
    COUNT(DISTINCT PED.PostId) AS UniquePostsEdited,
    MAX(PED.EditDate) AS LastEditDate,
    AVG(PED.RollingEditCount) AS AvgRollingEditCount,
    STRING_AGG(PED_comments.distinct_edit_comment, ' | ') AS RecentEditSummaries,
    COUNT(DISTINCT QAI.QuestionId) AS QuestionsEngaged,
    COUNT(DISTINCT QAI.AnswerId) AS AnswersEngaged,
    SUM(CASE WHEN QAI.AnswerAcceptanceStatus = 'Accepted' THEN 1 ELSE 0 END) AS AcceptedAnswersReceived,
    AVG(QAI.QuestionScore) AS AvgQuestionScoreInEngagement,
    SUM(CASE WHEN QAI.IsPerformanceBenchmarkingQuestion THEN 1 ELSE 0 END) AS PerformanceBenchmarkingQuestionsCount,
    SUM(COALESCE(QAI.HighRepUserVotesOnQuestion, 0)) AS TotalHighRepUserVotes,
    AVG(RPA.PostRankByUserAndType) AS AvgPostRankOverall,
    AVG(RPA.DailyAvgUserScore) AS AvgDailyScoreTrend,
    COUNT(DISTINCT PLA.PostId) AS PostsWithLinksAnalyzed,
    SUM(COALESCE(PLA.DuplicateLinkCount,0)) AS TotalDuplicateLinks,
    MAX(COALESCE(CASE WHEN PLA.HasHighScoreRelatedQuestion THEN 1 ELSE 0 END, 0)) = 1 AS HasAnyHighScoreRelatedQuestion,
    CAST(UAS.Reputation AS numeric) * 0.15
    + CAST(UAS.TotalPostScore AS numeric) * 0.08
    + CAST(COALESCE(BSA.GoldBadges, 0) AS numeric) * 100
    + CAST(COALESCE(BSA.SilverBadges, 0) AS numeric) * 20
    + CAST(COUNT(DISTINCT QAI.QuestionId) + COUNT(DISTINCT QAI.AnswerId) AS numeric) * 5
    + CAST(SUM(CASE WHEN QAI.AnswerAcceptanceStatus = 'Accepted' THEN 1 ELSE 0 END) AS numeric) * 50
    + CAST(COUNT(DISTINCT PED.PostId) AS numeric) * 10
    + (SELECT COUNT(DISTINCT T.Id) FROM Tags T WHERE T.TagName = ANY(string_to_array(UAS.TopTagsInPosts, ', '))) * 1.5
    + (CASE WHEN MAX(CASE WHEN QAI.IsPerformanceBenchmarkingQuestion THEN 1 ELSE 0 END) = 1 THEN 25 ELSE 0 END)
    + (CASE WHEN EXISTS (
            SELECT 1 FROM PostHistory PH_Closure WHERE PH_Closure.UserId = UAS.UserId AND PH_Closure.PostHistoryTypeId = 10 AND PH_Closure.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months')
         ) THEN -50 ELSE 0 END)
    AS ExpertContributorScore
FROM UserActivitySummary UAS
LEFT JOIN BadgeAchievementSummary BSA ON UAS.UserId = BSA.UserId
LEFT JOIN PostEditHistoryDetails PED ON UAS.UserId = PED.UserId
LEFT JOIN (
    SELECT
      UserId,
      PostId,
      EditDate,
      EditComment,
      ROW_NUMBER() OVER (PARTITION BY UserId, EditComment ORDER BY EditDate DESC) as rn,
      EditComment AS distinct_edit_comment
    FROM PostEditHistoryDetails
) PED_comments ON UAS.UserId = PED_comments.UserId AND PED_comments.rn = 1
LEFT JOIN QuestionAnswerInteractions QAI ON UAS.UserId = QAI.QuestionOwnerId OR UAS.UserId = QAI.AnswerOwnerId
LEFT JOIN RankedPostsAndAnswers RPA ON UAS.UserId = RPA.OwnerUserId
LEFT JOIN PostLinkAggregates PLA ON RPA.PostId = PLA.PostId
WHERE UAS.QuestionCount > 0
  AND UAS.AnswerCount > 0
  AND UAS.DisplayName IS NOT NULL
  AND UAS.DisplayName <> ''
  AND (
      UAS.TopTagsInPosts LIKE '%<sql>%'
      OR UAS.TopTagsInPosts LIKE '%<java>%'
      OR UAS.TopTagsInPosts LIKE '%<python>%'
  )
GROUP BY
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.LastAccessDate,
    UAS.TotalPosts,
    UAS.QuestionCount,
    UAS.AnswerCount,
    UAS.TotalPostScore,
    UAS.TopTagsInPosts,
    UAS.AvgCommentScorePerUserPost,
    BSA.TotalBadges,
    BSA.GoldBadges,
    BSA.SilverBadges,
    BSA.LatestGoldBadgeName,
    UAS.UserCreationDate
ORDER BY ExpertContributorScore DESC, UAS.Reputation DESC
LIMIT 500;