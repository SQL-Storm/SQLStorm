-- {"query": "1923.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3987}
WITH UserBaseStats AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 AND P.OwnerUserId = U.Id THEN 1 ELSE 0 END), 0) AS TotalQuestionsAsked,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 AND P.OwnerUserId = U.Id THEN 1 ELSE 0 END), 0) AS TotalAnswersPosted,
        COALESCE(COUNT(DISTINCT C.Id), 0) AS TotalCommentsMade,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 AND V.UserId = U.Id THEN 1 ELSE 0 END), 0) AS UpvotesCast,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 AND V.UserId = U.Id THEN 1 ELSE 0 END), 0) AS DownvotesCast,
        MAX(GREATEST(COALESCE(U.LastAccessDate, U.CreationDate), COALESCE(P.LastActivityDate, TIMESTAMP '1900-01-01'), COALESCE(C.CreationDate, TIMESTAMP '1900-01-01'))) AS LastInteractionDate,
        (EXTRACT(EPOCH FROM (CAST(TIMESTAMP '2024-10-01 12:34:56' - U.CreationDate AS INTERVAL))) ) / (3600 * 24) AS DaysSinceCreation
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Votes AS V ON U.Id = V.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
    HAVING U.Reputation > 100
),
PostTagExplosion AS (
    SELECT
        P.Id AS PostId,
        TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'))) AS TagName
    FROM Posts AS P
    WHERE P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2 AND P.PostTypeId IN (1, 2)
),
PostDetailedAnalysis AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        COALESCE(P.ViewCount, 0) AS ViewCount,
        COALESCE(P.AnswerCount, 0) AS AnswerCount,
        COALESCE(P.FavoriteCount, 0) AS FavoriteCount,
        P.Title,
        P.Tags,
        P.ClosedDate,
        P.AcceptedAnswerId,
        (SELECT AVG(SA.Score) FROM Posts AS SA WHERE SA.ParentId = P.Id AND SA.PostTypeId = 2) AS AvgRelatedAnswerScore,
        (SELECT COUNT(DISTINCT PH.UserId) FROM PostHistory AS PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId IN (4, 5, 6, 8)) AS DistinctEditorCount,
        EXISTS (SELECT 1 FROM PostLinks PL WHERE PL.PostId = P.Id AND PL.LinkTypeId = 3 AND PL.RelatedPostId <> P.Id) AS IsDuplicateSource,
        CASE
            WHEN EXISTS (SELECT 1 FROM PostTagExplosion PTE WHERE PTE.PostId = P.Id AND PTE.TagName IN ('javascript', 'reactjs')) AND
                 EXISTS (SELECT 1 FROM PostTagExplosion PTE WHERE PTE.PostId = P.Id AND PTE.TagName = 'reactjs') THEN 'JS_React_Framework'
            WHEN EXISTS (SELECT 1 FROM PostTagExplosion PTE WHERE PTE.PostId = P.Id AND PTE.TagName IN ('java', 'spring')) THEN 'Java_Spring_Framework'
            WHEN EXISTS (SELECT 1 FROM PostTagExplosion PTE WHERE PTE.PostId = P.Id AND PTE.TagName IN ('python', 'django')) THEN 'Python_Django_Framework'
            WHEN EXISTS (SELECT 1 FROM PostTagExplosion PTE WHERE PTE.PostId = P.Id AND PTE.TagName IN ('c#', '.net')) THEN 'CSharp_DotNet_Framework'
            WHEN P.Tags IS NULL OR P.Tags = '' THEN 'No_Tags'
            ELSE 'Other_Framework_Or_Tech'
        END AS TagFrameworkCategory,
        NULLIF(P.CommentCount, 0) AS ActualCommentCount,
        (CASE WHEN P.Body IS NULL THEN 0 ELSE (LENGTH(P.Body) - LENGTH(REPLACE(P.Body, 'code', ''))) / GREATEST(LENGTH('code'), 1) END) AS CodeKeywordCount,
        CASE WHEN P.AcceptedAnswerId IS NOT NULL AND (SELECT OwnerUserId FROM Posts WHERE Id = P.AcceptedAnswerId) <> P.OwnerUserId THEN TRUE ELSE FALSE END AS AcceptedByOtherUser
    FROM Posts AS P
    WHERE P.PostTypeId IN (1, 2)
      AND P.CreationDate BETWEEN TIMESTAMP '2023-01-01' AND TIMESTAMP '2023-12-31'
      AND P.Body IS NOT NULL AND LENGTH(P.Body) > 100
),
CommentSentiment AS (
    SELECT
        C.PostId,
        COUNT(C.Id) AS TotalCommentsOnPost,
        MAX(C.Score) AS MaxCommentScore,
        AVG(C.Score) AS AvgCommentScore,
        SUM(CASE WHEN C.Text LIKE '%thank%' OR C.Text LIKE '%helpful%' OR C.Text LIKE '%solved%' THEN 1 ELSE 0 END) AS PositiveCommentFlags,
        SUM(CASE WHEN C.Text LIKE '%bug%' OR C.Text LIKE '%error%' OR C.Text LIKE '%wrong%' OR C.Text LIKE '%clarify%' THEN 1 ELSE 0 END) AS ConstructiveCommentFlags
    FROM Comments AS C
    WHERE C.CreationDate >= TIMESTAMP '2023-01-01' AND C.Text IS NOT NULL
    GROUP BY C.PostId
),
PostAggregatedMetrics AS (
    SELECT
        PDA.PostId,
        PDA.PostTypeId,
        PDA.OwnerUserId,
        PDA.PostCreationDate,
        PDA.PostScore,
        PDA.ViewCount,
        PDA.AnswerCount,
        PDA.FavoriteCount,
        PDA.Title,
        PDA.Tags,
        PDA.ClosedDate,
        PDA.AcceptedAnswerId,
        PDA.AvgRelatedAnswerScore,
        PDA.DistinctEditorCount,
        PDA.IsDuplicateSource,
        PDA.TagFrameworkCategory,
        PDA.ActualCommentCount,
        PDA.CodeKeywordCount,
        PDA.AcceptedByOtherUser,
        COALESCE(CS.TotalCommentsOnPost, 0) AS RelatedCommentsCount,
        CS.MaxCommentScore,
        CS.AvgCommentScore,
        CS.PositiveCommentFlags,
        CS.ConstructiveCommentFlags,
        ROW_NUMBER() OVER (PARTITION BY PDA.OwnerUserId ORDER BY PDA.PostScore DESC, PDA.PostCreationDate DESC) AS PostRankByUser,
        RANK() OVER (PARTITION BY PDA.TagFrameworkCategory ORDER BY PDA.ViewCount DESC, PDA.PostScore DESC) AS ViewRankByTagCategory,
        AVG(PDA.PostScore) OVER (PARTITION BY PDA.TagFrameworkCategory) AS AvgTagCategoryScore,
        COUNT(PDA.PostId) OVER (PARTITION BY PDA.OwnerUserId) AS UserTotalPostsInPeriod,
        AVG(PDA.PostScore) OVER (PARTITION BY PDA.OwnerUserId ORDER BY PDA.PostCreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningAvgUserPostScore
    FROM PostDetailedAnalysis AS PDA
    LEFT JOIN CommentSentiment AS CS ON PDA.PostId = CS.PostId
),
UserPostCombined AS (
    SELECT
        UBS.UserId,
        UBS.DisplayName,
        UBS.Reputation,
        UBS.TotalQuestionsAsked,
        UBS.TotalAnswersPosted,
        UBS.TotalCommentsMade,
        UBS.UpvotesCast,
        UBS.DownvotesCast,
        UBS.LastInteractionDate,
        UBS.DaysSinceCreation,
        PAM.PostId,
        PAM.PostTypeId,
        PAM.PostCreationDate,
        PAM.PostScore,
        PAM.ViewCount,
        PAM.AnswerCount,
        PAM.FavoriteCount,
        PAM.Title,
        PAM.Tags,
        PAM.ClosedDate,
        PAM.AcceptedAnswerId,
        PAM.AvgRelatedAnswerScore,
        PAM.DistinctEditorCount,
        PAM.IsDuplicateSource,
        PAM.TagFrameworkCategory,
        PAM.ActualCommentCount,
        PAM.CodeKeywordCount,
        PAM.AcceptedByOtherUser,
        PAM.RelatedCommentsCount,
        PAM.MaxCommentScore,
        PAM.AvgCommentScore,
        PAM.PositiveCommentFlags,
        PAM.ConstructiveCommentFlags,
        PAM.PostRankByUser,
        PAM.ViewRankByTagCategory,
        PAM.AvgTagCategoryScore,
        PAM.UserTotalPostsInPeriod,
        PAM.RunningAvgUserPostScore,
        (EXTRACT(EPOCH FROM (CAST(TIMESTAMP '2024-10-01 12:34:56' - PAM.PostCreationDate AS INTERVAL)))) / (3600 * 24) AS PostAgeInDays,
        (PAM.PostScore * 0.4 +
         COALESCE(PAM.AvgRelatedAnswerScore, 0) * 0.2 +
         PAM.RelatedCommentsCount * 0.1 +
         PAM.FavoriteCount * 0.15 +
         (CASE WHEN PAM.AcceptedAnswerId IS NOT NULL THEN 10 ELSE 0 END) * 0.15
        ) AS WeightedPostScore,
        PAM.OwnerUserId
    FROM UserBaseStats AS UBS
    INNER JOIN PostAggregatedMetrics AS PAM ON UBS.UserId = PAM.OwnerUserId
    WHERE PAM.PostRankByUser <= 5
      AND PAM.ViewRankByTagCategory <= 10
      AND PAM.ActualCommentCount IS NOT NULL
      AND PAM.IsDuplicateSource = FALSE
),
HighlyEngagedQuestions AS (
    SELECT
        UPC.PostId,
        UPC.Title,
        UPC.OwnerUserId,
        UPC.DisplayName AS OwnerDisplayName,
        UPC.Reputation,
        UPC.PostScore,
        UPC.ViewCount,
        UPC.FavoriteCount,
        UPC.TagFrameworkCategory,
        UPC.WeightedPostScore,
        UPC.PostAgeInDays,
        UPC.RunningAvgUserPostScore,
        UPC.AcceptedByOtherUser,
        UPC.PostCreationDate,
        'ActiveQuestion_Segment' AS EntryType,
        UPC.PositiveCommentFlags,
        UPC.ConstructiveCommentFlags,
        UPC.AvgRelatedAnswerScore,
        UPC.ActualCommentCount
    FROM UserPostCombined AS UPC
    WHERE UPC.PostTypeId = 1
      AND UPC.PostScore > 50
      AND UPC.ViewCount > 5000
      AND UPC.TotalQuestionsAsked > 0
      AND UPC.PostAgeInDays < 365
      AND UPC.PositiveCommentFlags > COALESCE(UPC.ConstructiveCommentFlags, 0)
      AND UPC.AvgRelatedAnswerScore IS NOT NULL AND UPC.AvgRelatedAnswerScore > 15
      AND UPC.ActualCommentCount > 5
),
ExpertContributorAnswers AS (
    SELECT
        UPC.PostId,
        UPC.Title,
        UPC.OwnerUserId,
        UPC.DisplayName AS OwnerDisplayName,
        UPC.Reputation,
        UPC.PostScore,
        UPC.ViewCount,
        UPC.FavoriteCount,
        UPC.TagFrameworkCategory,
        UPC.WeightedPostScore,
        UPC.PostAgeInDays,
        UPC.RunningAvgUserPostScore,
        UPC.AcceptedByOtherUser,
        UPC.PostCreationDate,
        'ExpertAnswer_Segment' AS EntryType,
        UPC.AcceptedAnswerId,
        UPC.PostRankByUser,
        UPC.CodeKeywordCount
    FROM UserPostCombined AS UPC
    WHERE UPC.PostTypeId = 2
      AND UPC.PostScore > 30
      AND UPC.Reputation > 7500
      AND UPC.AcceptedAnswerId IS NOT NULL
      AND UPC.PostRankByUser = 1
      AND UPC.CodeKeywordCount > 3
      AND UPC.PostAgeInDays < 180
)
SELECT
    FinalOutput.PostId,
    FinalOutput.Title,
    FinalOutput.OwnerDisplayName,
    FinalOutput.Reputation,
    FinalOutput.PostScore,
    FinalOutput.ViewCount,
    FinalOutput.FavoriteCount,
    FinalOutput.TagFrameworkCategory,
    FinalOutput.WeightedPostScore,
    FinalOutput.PostAgeInDays,
    FinalOutput.RunningAvgUserPostScore,
    FinalOutput.AcceptedByOtherUser,
    FinalOutput.EntryType,
    (SELECT COUNT(DISTINCT C.UserId)
     FROM Comments AS C
     WHERE C.PostId = FinalOutput.PostId
       AND C.CreationDate >= FinalOutput.PostCreationDate
       AND C.Score > 0) AS UniquePositiveCommentersCount,
    (SELECT PH.Text FROM PostHistory PH WHERE PH.PostId = FinalOutput.PostId AND PH.PostHistoryTypeId = 5 ORDER BY PH.CreationDate DESC LIMIT 1) AS LatestBodyEditSnapshot
FROM (
    SELECT
        HQ.PostId, HQ.Title, HQ.OwnerDisplayName, HQ.Reputation, HQ.PostScore, HQ.ViewCount, HQ.FavoriteCount,
        HQ.TagFrameworkCategory, HQ.WeightedPostScore, HQ.PostAgeInDays, HQ.RunningAvgUserPostScore, HQ.AcceptedByOtherUser,
        HQ.EntryType, HQ.PostCreationDate
    FROM HighlyEngagedQuestions AS HQ
    WHERE HQ.WeightedPostScore > 80

    UNION ALL

    SELECT
        EA.PostId, EA.Title, EA.OwnerDisplayName, EA.Reputation, EA.PostScore, EA.ViewCount, EA.FavoriteCount,
        EA.TagFrameworkCategory, EA.WeightedPostScore, EA.PostAgeInDays, EA.RunningAvgUserPostScore, EA.AcceptedByOtherUser,
        EA.EntryType, EA.PostCreationDate
    FROM ExpertContributorAnswers AS EA
    WHERE EA.WeightedPostScore > 60
      AND EA.RunningAvgUserPostScore > 20
) AS FinalOutput
ORDER BY FinalOutput.WeightedPostScore DESC, FinalOutput.Reputation DESC, FinalOutput.PostAgeInDays ASC
LIMIT 1000;