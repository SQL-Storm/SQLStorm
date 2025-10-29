-- {"query": "1746.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3375}
WITH UserEngagementSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate AS UserLastAccessDate,
        COALESCE(SUM(CASE WHEN P.PostTypeId IN (1, 2, 4, 5) THEN 1 ELSE 0 END), 0) AS TotalPosts,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS TotalQuestions,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalAnswers,
        COALESCE(COUNT(DISTINCT C.Id), 0) AS TotalComments,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpvotesReceived,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownvotesReceived,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 AND P.Id = Q.AcceptedAnswerId THEN 1 ELSE 0 END), 0) AS AcceptedAnswersCount,
        MAX(COALESCE(P.LastActivityDate, C.CreationDate, U.LastAccessDate)) AS LatestContributionDate,
        CAST((EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - U.CreationDate)) / (60 * 60 * 24)) AS int) AS AccountAgeDays
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON P.Id = V.PostId
    LEFT JOIN Posts Q ON P.ParentId = Q.Id AND P.PostTypeId = 2
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostDetailedMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.CommentCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.ClosedDate,
        P.AcceptedAnswerId,
        LENGTH(P.Body) AS BodyLength,
        (SELECT COALESCE(COUNT(PH.Id), 0) FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId IN (4,5,6)) AS EditCount,
        (SELECT MIN(PH2.CreationDate) FROM PostHistory PH2 WHERE PH2.PostId = P.Id AND PH2.PostHistoryTypeId IN (4,5,6) AND PH2.CreationDate > P.CreationDate) AS FirstEditDate,
        COALESCE(P.Title, SUBSTRING(P.Body, 1, LEAST(LENGTH(P.Body), 100))) AS PostTitleSnippet,
        CASE
            WHEN P.PostTypeId = 1 AND P.Tags IS NOT NULL THEN string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><')
            ELSE NULL
        END AS ParsedTagsArray,
        CR.Name AS CloseReason
    FROM Posts P
    JOIN PostTypes PT ON P.PostTypeId = PT.Id
    LEFT JOIN PostHistory PH_Close ON P.Id = PH_Close.PostId AND PH_Close.PostHistoryTypeId = 10 AND PH_Close.CreationDate = P.ClosedDate
    LEFT JOIN CloseReasonTypes CR ON CAST(PH_Close.Comment AS int) = CR.Id
    WHERE P.PostTypeId IN (1, 2) AND P.OwnerUserId IS NOT NULL
),
TagPopularity AS (
    SELECT
        tag AS TagName,
        COUNT(PDM.PostId) AS QuestionCountWithTag,
        COALESCE(SUM(PDM.Score), 0) AS TotalTagScore,
        COALESCE(AVG(PDM.Score), 0.0) AS AvgTagScore
    FROM PostDetailedMetrics PDM,
         UNNEST(PDM.ParsedTagsArray) AS tag
    WHERE PDM.PostTypeId = 1 AND PDM.ParsedTagsArray IS NOT NULL
    GROUP BY tag
),
GlobalAvgTagScore AS (
    SELECT AVG(AvgTagScore) AS GlobalAverage FROM TagPopularity
),
PostHistoryTimeline AS (
    SELECT
        PH.PostId,
        PH.CreationDate AS HistoryDate,
        PHT.Name AS HistoryTypeName,
        PH.PostHistoryTypeId,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate, PH.Id) AS EventSequence,
        LAG(PH.CreationDate, 1, PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate, PH.Id) AS PreviousEventDate,
        LEAD(PH.CreationDate, 1, PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate, PH.Id) AS NextEventDate,
        EXTRACT(EPOCH FROM (PH.CreationDate - LAG(PH.CreationDate, 1, PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate, PH.Id))) AS TimeSincePrevEventSeconds,
        PH.Comment,
        PH.UserId AS HistoryUserId
    FROM PostHistory PH
    JOIN PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
),
UserBadgeSummary AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        COALESCE(SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges,
        COALESCE(SUM(CASE WHEN B.TagBased = TRUE THEN 1 ELSE 0 END), 0) AS TagBasedBadges,
        COALESCE(SUM(CASE WHEN B.TagBased = FALSE THEN 1 ELSE 0 END), 0) AS NamedBadges,
        MAX(B.Date) AS LatestBadgeDate
    FROM Badges B
    GROUP BY B.UserId
),
TrendingTags AS (
    SELECT
        TP.TagName
    FROM TagPopularity TP
    CROSS JOIN GlobalAvgTagScore GATS
    WHERE TP.AvgTagScore > GATS.GlobalAverage * 1.5
      AND TP.QuestionCountWithTag > 100
),
UserPostTagActivity AS (
    SELECT
        PDM.OwnerUserId AS UserId,
        tag AS TagName,
        COUNT(PDM.PostId) AS UserQuestionsWithTag,
        SUM(PDM.Score) AS UserTagScore,
        AVG(PDM.Score) AS UserAvgTagScore,
        MAX(PDM.PostCreationDate) AS LastPostDateForTag
    FROM PostDetailedMetrics PDM,
         UNNEST(PDM.ParsedTagsArray) AS tag
    WHERE PDM.PostTypeId = 1 AND PDM.ParsedTagsArray IS NOT NULL
    GROUP BY PDM.OwnerUserId, tag
),
HighlyEngagedUsers AS (
    SELECT
        UES.UserId,
        UES.DisplayName,
        UES.Reputation,
        UES.TotalPosts,
        UES.TotalComments,
        UBS.GoldBadges,
        UBS.SilverBadges,
        UBS.BronzeBadges,
        UES.TotalUpvotesReceived,
        UES.TotalDownvotesReceived,
        UES.AcceptedAnswersCount,
        UES.LatestContributionDate,
        UES.AccountAgeDays,
        (UES.Reputation * (UES.TotalPosts + UES.TotalComments * 0.5) +
         (COALESCE(UBS.GoldBadges,0) * 100 + COALESCE(UBS.SilverBadges,0) * 50 + COALESCE(UBS.BronzeBadges,0) * 10) +
         UES.TotalUpvotesReceived * 2 - UES.TotalDownvotesReceived * 1.5 +
         UES.AcceptedAnswersCount * 50) AS CompositeEngagementScore,
        RANK() OVER (ORDER BY (UES.Reputation * (UES.TotalPosts + UES.TotalComments * 0.5) +
                               (COALESCE(UBS.GoldBadges,0) * 100 + COALESCE(UBS.SilverBadges,0) * 50 + COALESCE(UBS.BronzeBadges,0) * 10) +
                               UES.TotalUpvotesReceived * 2 - UES.TotalDownvotesReceived * 1.5 +
                               UES.AcceptedAnswersCount * 50) DESC) AS OverallEngagementRank
    FROM UserEngagementSummary UES
    LEFT JOIN UserBadgeSummary UBS ON UES.UserId = UBS.UserId
    WHERE UES.TotalPosts > 10
      AND UES.AccountAgeDays > 30
      AND UES.Reputation > 100
),
ActivePostMaintenanceUsers AS (
    SELECT
        PDM.OwnerUserId AS UserId,
        COUNT(PDM.PostId) AS UserPostCount
    FROM PostDetailedMetrics PDM
    LEFT JOIN PostHistoryTimeline PHT_reopen ON PHT_reopen.PostId = PDM.PostId AND PHT_reopen.PostHistoryTypeId = 11
    WHERE PDM.EditCount > 1
      AND PDM.PostTypeId IN (1, 2)
      AND (PDM.ClosedDate IS NULL OR PHT_reopen.HistoryDate > PDM.ClosedDate)
    GROUP BY PDM.OwnerUserId
    HAVING COUNT(PDM.PostId) >= 5
),
UsersWithTrendingTagPosts AS (
    SELECT
        UPTA.UserId,
        COUNT(DISTINCT UPTA.TagName) AS TrendingTagCount,
        (SELECT UPTA_inner.TagName
         FROM UserPostTagActivity UPTA_inner
         JOIN TrendingTags TT_inner ON UPTA_inner.TagName = TT_inner.TagName
         WHERE UPTA_inner.UserId = UPTA.UserId
         ORDER BY UPTA_inner.UserQuestionsWithTag DESC, UPTA_inner.LastPostDateForTag DESC
         LIMIT 1) AS MostActiveTrendingTag
    FROM UserPostTagActivity UPTA
    JOIN TrendingTags TT ON UPTA.TagName = TT.TagName
    GROUP BY UPTA.UserId
    HAVING COUNT(DISTINCT UPTA.TagName) > 0
)
SELECT
    HEU.DisplayName AS User_DisplayName,
    HEU.Reputation,
    HEU.TotalPosts,
    HEU.TotalComments,
    HEU.GoldBadges,
    HEU.SilverBadges,
    HEU.BronzeBadges,
    HEU.TotalUpvotesReceived,
    HEU.TotalDownvotesReceived,
    HEU.AcceptedAnswersCount,
    HEU.AccountAgeDays,
    HEU.CompositeEngagementScore,
    HEU.OverallEngagementRank,
    UTTP.TrendingTagCount,
    UTTP.MostActiveTrendingTag,
    CASE
        WHEN APMU.UserId IS NOT NULL THEN 'Yes'
        ELSE 'No'
    END AS IsActivePostMaintainer,
    NTH_VALUE(HEU.DisplayName, 5) OVER (ORDER BY HEU.CompositeEngagementScore DESC) AS FifthHighestEngagedUser,
    NTILE(5) OVER (ORDER BY HEU.CompositeEngagementScore DESC) AS EngagementQuintile,
    (SELECT AVG(PDM.Score)
     FROM PostDetailedMetrics PDM
     WHERE PDM.OwnerUserId = HEU.UserId AND PDM.PostTypeId = 1) AS UserAvgQuestionScore,
    (SELECT AVG(PDM_global.Score)
     FROM PostDetailedMetrics PDM_global
     WHERE PDM_global.PostTypeId = 1) AS GlobalAvgQuestionScore,
    COALESCE((
        SELECT AVG(EXTRACT(EPOCH FROM (PDM_inner.FirstEditDate - PDM_inner.PostCreationDate))) / 3600.0
        FROM PostDetailedMetrics PDM_inner
        WHERE PDM_inner.OwnerUserId = HEU.UserId
          AND PDM_inner.PostTypeId = 1
          AND PDM_inner.FirstEditDate IS NOT NULL
          AND PDM_inner.FirstEditDate > PDM_inner.PostCreationDate
    ), 0.0) AS AvgTimeUntilFirstEditHours,
    CASE
        WHEN U.AboutMe ILIKE '%sql%' OR U.AboutMe ILIKE '%database%' OR U.AboutMe ILIKE '%data%' THEN 'SQL/Data Focus'
        WHEN U.AboutMe ILIKE '%web%' OR U.AboutMe ILIKE '%javascript%' OR U.AboutMe ILIKE '%frontend%' THEN 'Web Focus'
        WHEN U.AboutMe IS NULL OR U.AboutMe = '' THEN 'No AboutMe'
        ELSE 'Other Focus'
    END AS UserAboutMeCategory,
    CAST(HEU.TotalUpvotesReceived AS numeric) / NULLIF(CAST(HEU.TotalDownvotesReceived AS numeric), 0) AS UpvoteToDownvoteRatio,
    (SELECT
        COALESCE(SUM(CASE WHEN PL.LinkTypeId = 1 AND P.Id = PL.RelatedPostId THEN 1 ELSE 0 END), 0)
     FROM Posts P
     LEFT JOIN PostLinks PL ON P.Id = PL.RelatedPostId
     WHERE P.OwnerUserId = HEU.UserId AND P.PostTypeId = 1
    ) AS TotalIncomingLinksToQuestions
FROM HighlyEngagedUsers HEU
LEFT JOIN UsersWithTrendingTagPosts UTTP ON HEU.UserId = UTTP.UserId
LEFT JOIN ActivePostMaintenanceUsers APMU ON HEU.UserId = APMU.UserId
JOIN Users U ON HEU.UserId = U.Id
WHERE HEU.OverallEngagementRank <= 100
  AND (U.Location IS NOT NULL AND U.Location != '' AND (U.Location ILIKE '%usa%' OR U.Location ILIKE '%uk%'))
  AND HEU.CompositeEngagementScore > (SELECT AVG(CompositeEngagementScore) * 1.5 FROM HighlyEngagedUsers)
ORDER BY HEU.OverallEngagementRank ASC, HEU.CompositeEngagementScore DESC
LIMIT 50;