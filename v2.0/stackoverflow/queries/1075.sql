-- {"query": "1075.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2832}
WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName AS UserName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate AS UserLastAccessDate,
        U.WebsiteUrl,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserTotalUpVotes,
        U.DownVotes AS UserTotalDownVotes,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionsPosted,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswersPosted,
        COALESCE(COUNT(P.Id), 0) AS TotalPostsByOwner,
        MAX(P.CreationDate) AS LastPostCreationDate,
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - U.CreationDate)) / (24 * 3600) AS AccountAgeDays,
        COALESCE(NULLIF(SUM(CASE WHEN P.PostTypeId = 1 THEN P.ViewCount ELSE 0 END), 0) * 1.0 / NULLIF(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0), 0) AS AvgQuestionViewCount,
        COALESCE(NULLIF(SUM(P.Score), 0) * 1.0 / NULLIF(COUNT(P.Id), 0), 0) AS AvgPostScoreByOwner,
        (SELECT COALESCE(AVG(Reputation), 0) FROM Users WHERE CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 year') AS AvgRecentUserReputation
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.WebsiteUrl, U.Views, U.UpVotes, U.DownVotes
),
PostDetails AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount AS PostViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.ClosedDate,
        P.Title,
        P.Tags,
        LENGTH(P.Body) AS BodyLength,
        REPLACE(REPLACE(REPLACE(SUBSTRING(P.Body FROM 1 FOR 150), CHR(10), ' '), CHR(13), ' '), '  ', ' ') AS BodySnippet,
        COALESCE(C.CommentCount, 0) AS TotalComments,
        COALESCE(V_Up.UpVotes, 0) AS TotalUpVotes,
        COALESCE(V_Down.DownVotes, 0) AS TotalDownVotes,
        (SELECT MAX(PA.Score) FROM Posts AS PA WHERE PA.Id = P.AcceptedAnswerId AND PA.PostTypeId = 2) AS AcceptedAnswerScore,
        P.PostTypeId
    FROM Posts AS P
    LEFT JOIN (SELECT PostId, COUNT(Id) AS CommentCount FROM Comments GROUP BY PostId) AS C ON P.Id = C.PostId
    LEFT JOIN (SELECT PostId, COUNT(Id) AS UpVotes FROM Votes WHERE VoteTypeId = 2 GROUP BY PostId) AS V_Up ON P.Id = V_Up.PostId
    LEFT JOIN (SELECT PostId, COUNT(Id) AS DownVotes FROM Votes WHERE VoteTypeId = 3 GROUP BY PostId) AS V_Down ON P.Id = V_Down.PostId
    WHERE P.PostTypeId = 1
),
PostHistoryTimeline AS (
    SELECT
        PH.PostId,
        PH.Id AS HistoryId,
        PH.PostHistoryTypeId,
        PH.CreationDate AS HistoryDate,
        PH.UserId AS HistoryUserId,
        PH.Comment,
        LAG(PH.CreationDate, 1, PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PrevHistoryDate
    FROM PostHistory AS PH
    WHERE PH.PostHistoryTypeId IN (4, 5, 6, 8, 10, 11, 12, 13, 14, 15, 19, 20)
),
PostEditSummary AS (
    SELECT
        PH_Timeline.PostId,
        COUNT(CASE WHEN PH_Timeline.PostHistoryTypeId IN (4, 5, 6, 8) THEN 1 ELSE NULL END) AS EditCount,
        MIN(CASE WHEN PH_Timeline.PostHistoryTypeId IN (4, 5, 6) THEN PH_Timeline.HistoryDate ELSE NULL END) AS FirstEditDate,
        MAX(CASE WHEN PH_Timeline.PostHistoryTypeId IN (4, 5, 6) THEN PH_Timeline.HistoryDate ELSE NULL END) AS LastEditDate,
        COALESCE(AVG(EXTRACT(EPOCH FROM (PH_Timeline.HistoryDate - PH_Timeline.PrevHistoryDate)) / (24 * 3600)), 0) AS AvgDaysBetweenEvents,
        MAX(CASE WHEN PH_Timeline.PostHistoryTypeId = 10 THEN PH_Timeline.Comment ELSE NULL END) AS CloseReasonIdComment
    FROM PostHistoryTimeline AS PH_Timeline
    GROUP BY PH_Timeline.PostId
),
TagMetrics AS (
    SELECT
        TRIM(value) AS TagName,
        Q.PostId,
        Q.PostScore
    FROM PostDetails AS Q,
    LATERAL (
        SELECT UNNEST(string_to_array(SUBSTRING(Q.Tags FROM 2 FOR LENGTH(Q.Tags)-2), '><')) AS value
    ) AS t
    WHERE Q.Tags IS NOT NULL AND LENGTH(Q.Tags) > 2
),
AggregatedTagMetrics AS (
    SELECT
        TM.TagName,
        COUNT(TM.PostId) AS TaggedQuestionCount,
        COALESCE(AVG(TM.PostScore), 0) AS AvgTagScore,
        RANK() OVER (ORDER BY COUNT(TM.PostId) DESC, COALESCE(AVG(TM.PostScore), 0) DESC) AS TagPopularityRank
    FROM TagMetrics AS TM
    GROUP BY TM.TagName
)
SELECT
    PD.PostId,
    COALESCE(UE.UserName, CAST(PD.OwnerUserId AS varchar), 'Community Wiki / Deleted User') AS QuestionOwnerName,
    PD.Title,
    PD.BodySnippet,
    PD.PostCreationDate,
    PD.PostScore,
    PD.PostViewCount,
    PD.AnswerCount,
    PD.TotalComments,
    PD.TotalUpVotes,
    PD.TotalDownVotes,
    PD.AcceptedAnswerScore,
    PES.EditCount,
    COALESCE(PD.PostScore * 1.0 / NULLIF(PD.PostViewCount, 0), 0) AS ScorePerViewRatio,
    COALESCE(UE.AnswersPosted * 1.0 / NULLIF(UE.QuestionsPosted + UE.AnswersPosted, 0), 0) AS OwnerEngagementRatio,
    TRIM(SUBSTRING(PD.Tags FROM 2 FOR POSITION('><' IN (PD.Tags || '><')) - 2)) AS PrimaryTag,
    NULLIF(TRIM(
        SUBSTRING(
            PD.Tags FROM POSITION('><' IN PD.Tags)+2 FOR
            POSITION('><' IN (SUBSTRING(PD.Tags FROM POSITION('><' IN PD.Tags)+2) || '><')) - 1
        )
    ), '') AS SecondaryTag,
    CASE
        WHEN PD.ClosedDate IS NOT NULL THEN
            'Closed' || COALESCE(' (' || CRT.Name || ')', ' (Reason Unknown)')
        WHEN PD.AnswerCount > 0 AND PD.AcceptedAnswerScore IS NOT NULL THEN 'Answered & Accepted'
        WHEN PD.AnswerCount > 0 THEN 'Answered'
        ELSE 'Open'
    END AS PostStatus,
    RANK() OVER (ORDER BY PD.PostScore DESC, PD.PostViewCount DESC, PD.AnswerCount DESC, PD.TotalComments DESC) AS GlobalEngagementRank,
    (PD.PostScore * 0.7 + PD.TotalUpVotes * 0.4 + PD.TotalComments * 0.2 + COALESCE(PES.EditCount, 0) * 0.1 - PD.TotalDownVotes * 0.1 + COALESCE(PD.FavoriteCount, 0) * 0.3) AS EngagementIndex,
    COALESCE(EXTRACT(DAY FROM (CAST('2024-10-01 12:34:56' AS timestamp) - PES.LastEditDate)), -1) AS DaysSinceLastEdit,
    UE.AvgRecentUserReputation,
    ATM_Primary.TaggedQuestionCount AS PrimaryTagPopularity,
    ATM_Primary.AvgTagScore AS PrimaryTagAvgScore,
    ATM_Primary.TagPopularityRank AS PrimaryTagRank,
    COALESCE(LOWER(SPLIT_PART(SUBSTRING(UE.WebsiteUrl FROM POSITION('://' IN UE.WebsiteUrl)+3), '/', 1)), 'N/A') AS UserWebsiteDomain,
    COALESCE(UE.UserProfileViews, 0) AS OwnerProfileViews,
    COALESCE(UE.AccountAgeDays, 0) AS OwnerAccountAgeDays
FROM PostDetails AS PD
LEFT JOIN UserEngagement AS UE ON PD.OwnerUserId = UE.UserId
LEFT JOIN PostEditSummary AS PES ON PD.PostId = PES.PostId
LEFT JOIN CloseReasonTypes AS CRT ON PES.CloseReasonIdComment = CAST(CRT.Id AS varchar)
LEFT JOIN AggregatedTagMetrics AS ATM_Primary ON ATM_Primary.TagName = TRIM(SUBSTRING(PD.Tags FROM 2 FOR POSITION('><' IN (PD.Tags || '><')) - 2))
WHERE
    PD.PostTypeId = 1
    AND PD.PostViewCount > 750
    AND PD.PostScore > 15
    AND UE.Reputation IS NOT NULL AND UE.Reputation > 500
    AND (PD.ClosedDate IS NULL OR PD.PostCreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3 year')
    AND (
        PD.Title ILIKE '%sql%' OR PD.Title ILIKE '%database%' OR PD.Title ILIKE '%performance%' OR PD.Title ILIKE '%optimization%'
        OR PD.Tags ILIKE '%<sql>%' OR PD.Tags ILIKE '%<database>%' OR PD.Tags ILIKE '%<performance>%'
    )
    AND PD.BodyLength > 100
ORDER BY
    EngagementIndex DESC,
    PD.PostCreationDate DESC
LIMIT 2000;