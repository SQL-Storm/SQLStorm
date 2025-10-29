WITH UserEngagementSummary AS (
    SELECT
        U.Id AS UserId,
        COALESCE(U.DisplayName, 'Anonymous User #' || U.Id) AS DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate AS UserLastAccessDate,
        U.UpVotes,
        U.DownVotes,
        U.Views AS UserProfileViews,
        U.Location,
        CASE
            WHEN U.Reputation >= 100000 THEN 'Legend'
            WHEN U.Reputation >= 25000 THEN 'Expert'
            WHEN U.Reputation >= 5000 THEN 'Experienced'
            WHEN U.Reputation >= 500 THEN 'Intermediate'
            ELSE 'Beginner'
        END AS ReputationTier,
        COALESCE(LENGTH(U.AboutMe), 0) AS AboutMeLength,
        (SELECT COUNT(DISTINCT B.Name) FROM Badges B WHERE B.UserId = U.Id) AS DistinctBadgesCount,
        (SELECT B.Name FROM Badges B WHERE B.UserId = U.Id GROUP BY B.Name ORDER BY COUNT(*) DESC, B.Name LIMIT 1) AS MostFrequentBadgeName,
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - U.LastAccessDate)) / 86400.0 AS DaysSinceLastActivity,
        CASE WHEN U.WebsiteUrl IS NOT NULL THEN TRUE ELSE FALSE END AS HasWebsiteUrl
    FROM
        Users U
    WHERE
        U.Reputation > 0 AND U.AccountId IS NOT NULL
),
PostDetailMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.OwnerUserId,
        COALESCE(P.Title, SUBSTRING(P.Body, 1, 50) || '...') AS PostTitleExcerpt,
        P.Tags,
        P.AnswerCount,
        P.CommentCount AS PostCommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        P.CommunityOwnedDate,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.Id END) AS EditCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN CR.Name END) AS LatestCloseReason,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate END) AS PostClosedHistoryDate,
        COUNT(DISTINCT PL_Linked.RelatedPostId) AS LinkedPostCount,
        COUNT(DISTINCT PL_Duplicate.RelatedPostId) AS DuplicatePostCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        SUM(CASE WHEN V.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteVoteCount,
        SUM(CASE WHEN V.VoteTypeId IN (2, 3) THEN 1 ELSE 0 END) AS TotalFeedbackVoteCount,
        (SELECT COUNT(DISTINCT C.Id) FROM Comments C WHERE C.PostId = P.Id) AS TotalCommentsOnPost,
        EXISTS (
            SELECT 1
            FROM Posts AS SelfAnswer
            WHERE SelfAnswer.ParentId = P.Id
              AND SelfAnswer.PostTypeId = 2
              AND SelfAnswer.OwnerUserId = P.OwnerUserId
        ) AS HasSelfAnswer,
        (SELECT array_agg(DISTINCT U_Voter.DisplayName)
         FROM Votes V_Inner
         JOIN Users U_Voter ON V_Inner.UserId = U_Voter.Id
         WHERE V_Inner.PostId = P.Id AND V_Inner.VoteTypeId IN (2, 3)
         GROUP BY V_Inner.PostId
         ORDER BY COUNT(*) DESC LIMIT 3) AS TopVotersForPostDisplayName,
        EXTRACT(EPOCH FROM (P.LastEditDate - P.CreationDate)) / 3600.0 AS HoursToFirstEdit,
        CASE
            WHEN P.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN P.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN P.AnswerCount > 0 THEN 'Has Answers'
            ELSE 'Open'
        END AS PostStatusCategory
    FROM
        Posts P
    JOIN
        PostTypes PT ON P.PostTypeId = PT.Id
    LEFT JOIN
        PostHistory PH ON P.Id = PH.PostId
    LEFT JOIN
        CloseReasonTypes CR ON PH.PostHistoryTypeId = 10 AND PH.Comment = CAST(CR.Id AS varchar)
    LEFT JOIN
        PostLinks PL_Linked ON P.Id = PL_Linked.PostId AND PL_Linked.LinkTypeId = 1
    LEFT JOIN
        PostLinks PL_Duplicate ON P.Id = PL_Duplicate.PostId AND PL_Duplicate.LinkTypeId = 3
    LEFT JOIN
        Votes V ON P.Id = V.PostId AND V.VoteTypeId IN (2, 3, 5)
    WHERE
        P.PostTypeId IN (1, 2)
    GROUP BY
        P.Id, P.PostTypeId, PT.Name, P.CreationDate, P.Score, P.ViewCount, P.OwnerUserId, P.Title, P.Body, P.Tags,
        P.AnswerCount, P.CommentCount, P.FavoriteCount, P.ClosedDate, P.CommunityOwnedDate, P.LastEditDate, P.AcceptedAnswerId
),
TagPerformance AS (
    SELECT
        PDM.PostId,
        UNNEST(string_to_array(TRIM(BOTH '<>' FROM PDM.Tags), '><')) AS TagName,
        PDM.PostScore,
        PDM.ViewCount,
        PDM.PostCreationDate
    FROM
        PostDetailMetrics PDM
    WHERE
        PDM.Tags IS NOT NULL AND PDM.Tags <> ''
)
SELECT
    UES.DisplayName,
    UES.Reputation,
    UES.ReputationTier,
    UES.MostFrequentBadgeName,
    UES.DaysSinceLastActivity,
    PDM.PostId,
    PDM.PostTypeName,
    PDM.PostTitleExcerpt,
    PDM.PostCreationDate,
    PDM.PostScore,
    PDM.ViewCount,
    PDM.PostCommentCount,
    PDM.FavoriteCount,
    PDM.UpVoteCount,
    PDM.DownVoteCount,
    PDM.TotalFeedbackVoteCount,
    PDM.LatestCloseReason,
    PDM.EditCount,
    PDM.LinkedPostCount,
    PDM.DuplicatePostCount,
    PDM.HasSelfAnswer,
    PDM.PostStatusCategory,
    TP.TagName,
    RANK() OVER (PARTITION BY UES.ReputationTier ORDER BY PDM.PostScore DESC, PDM.ViewCount DESC) AS RankWithinRepTierByPostScore,
    NTILE(5) OVER (ORDER BY PDM.ViewCount DESC, PDM.PostScore DESC) AS ViewScoreQuintile,
    AVG(PDM.PostScore) OVER (PARTITION BY PDM.PostTypeName, EXTRACT(YEAR FROM PDM.PostCreationDate)) AS AvgScoreForPostTypeYear,
    SUM(PDM.TotalFeedbackVoteCount) OVER (PARTITION BY UES.UserId) AS UserTotalFeedbackVotes,
    COALESCE(PDM.UpVoteCount, 0) - COALESCE(PDM.DownVoteCount, 0) AS NetVotes,
    (CAST(COALESCE(PDM.UpVoteCount, 0) - COALESCE(PDM.DownVoteCount, 0) AS numeric) / NULLIF(CAST(PDM.TotalFeedbackVoteCount AS numeric), 0)) AS NetVoteRatio,
    SQRT(CAST(PDM.ViewCount AS numeric) * CAST(COALESCE(PDM.FavoriteCount, 1) AS numeric)) AS EngagementIndex,
    UPPER(SUBSTRING(COALESCE(PDM.PostTitleExcerpt, 'NO TITLE') FROM 1 FOR 1)) AS InitialTitleChar,
    REPLACE(REPLACE(REPLACE(COALESCE(PDM.PostTitleExcerpt, ''), 'Stack Overflow', 'SO'), 'SQL', 'Database'), 'Postgres', 'PG') AS MungedTitle,
    PDM.HoursToFirstEdit,
    PDM.TopVotersForPostDisplayName,
    (SELECT COUNT(DISTINCT V_Type.Id)
     FROM Votes V_Type
     WHERE V_Type.PostId = PDM.PostId AND V_Type.VoteTypeId = (SELECT Id FROM VoteTypes WHERE Name = 'Favorite')) AS ActualFavoriteCountForPost,
    CASE
        WHEN UES.HasWebsiteUrl THEN 'User Has Website'
        ELSE 'User No Website'
    END AS UserWebsiteStatus,
    CASE
        WHEN PDM.PostScore > 100 AND PDM.ViewCount > 50000 THEN 'Viral Content'
        WHEN PDM.PostScore > 50 AND PDM.ViewCount > 10000 THEN 'High Impact'
        ELSE 'Standard'
    END AS ContentImpactLevel
FROM
    UserEngagementSummary UES
INNER JOIN
    PostDetailMetrics PDM ON UES.UserId = PDM.OwnerUserId
LEFT JOIN
    TagPerformance TP ON PDM.PostId = TP.PostId
WHERE
    UES.Reputation > 1000
    AND PDM.PostCreationDate >= DATE '2022-01-01'
    AND (TP.TagName IS NULL OR TP.TagName NOT LIKE '%-tag-spam%')
    AND (PDM.LatestCloseReason IS NULL OR PDM.LatestCloseReason NOT LIKE '%duplicate%')
    AND PDM.PostScore > (SELECT AVG(P_Inner.Score) FROM Posts P_Inner WHERE P_Inner.PostTypeId = PDM.PostTypeId)
    AND (PDM.HasSelfAnswer = FALSE OR PDM.AnswerCount > 1)
    AND UES.AboutMeLength > 50
    AND PDM.EditCount >= 1
    AND PDM.TotalFeedbackVoteCount > 5
UNION ALL
SELECT
    UES.DisplayName,
    UES.Reputation,
    UES.ReputationTier,
    UES.MostFrequentBadgeName,
    UES.DaysSinceLastActivity,
    PDM.PostId,
    PDM.PostTypeName,
    PDM.PostTitleExcerpt,
    PDM.PostCreationDate,
    PDM.PostScore,
    PDM.ViewCount,
    PDM.PostCommentCount,
    PDM.FavoriteCount,
    PDM.UpVoteCount,
    PDM.DownVoteCount,
    PDM.TotalFeedbackVoteCount,
    PDM.LatestCloseReason,
    PDM.EditCount,
    PDM.LinkedPostCount,
    PDM.DuplicatePostCount,
    PDM.HasSelfAnswer,
    PDM.PostStatusCategory,
    TP.TagName,
    RANK() OVER (PARTITION BY PDM.PostTypeName ORDER BY PDM.LinkedPostCount DESC, PDM.DuplicatePostCount DESC) AS RankWithinRepTierByPostScore,
    NTILE(5) OVER (ORDER BY PDM.LinkedPostCount DESC, PDM.DuplicatePostCount DESC) AS ViewScoreQuintile,
    AVG(PDM.PostScore) OVER (PARTITION BY PDM.PostTypeName, EXTRACT(YEAR FROM PDM.PostCreationDate)) AS AvgScoreForPostTypeYear,
    SUM(PDM.TotalFeedbackVoteCount) OVER (PARTITION BY UES.UserId) AS UserTotalFeedbackVotes,
    COALESCE(PDM.UpVoteCount, 0) - COALESCE(PDM.DownVoteCount, 0) AS NetVotes,
    (CAST(COALESCE(PDM.UpVoteCount, 0) - COALESCE(PDM.DownVoteCount, 0) AS numeric) / NULLIF(CAST(PDM.TotalFeedbackVoteCount AS numeric), 0)) AS NetVoteRatio,
    SQRT(CAST(PDM.ViewCount AS numeric) * CAST(COALESCE(PDM.FavoriteCount, 1) AS numeric)) AS EngagementIndex,
    UPPER(SUBSTRING(COALESCE(PDM.PostTitleExcerpt, 'NO TITLE') FROM 1 FOR 1)) AS InitialTitleChar,
    REPLACE(REPLACE(REPLACE(COALESCE(PDM.PostTitleExcerpt, ''), 'Stack Overflow', 'SO'), 'SQL', 'Database'), 'Postgres', 'PG') AS MungedTitle,
    PDM.HoursToFirstEdit,
    PDM.TopVotersForPostDisplayName,
    (SELECT COUNT(DISTINCT V_Type.Id)
     FROM Votes V_Type
     WHERE V_Type.PostId = PDM.PostId AND V_Type.VoteTypeId = (SELECT Id FROM VoteTypes WHERE Name = 'Favorite')) AS ActualFavoriteCountForPost,
    CASE
        WHEN UES.HasWebsiteUrl THEN 'User Has Website'
        ELSE 'User No Website'
    END AS UserWebsiteStatus,
    CASE
        WHEN PDM.PostScore > 100 AND PDM.ViewCount > 50000 THEN 'Viral Content'
        WHEN PDM.PostScore > 50 AND PDM.ViewCount > 10000 THEN 'High Impact'
        ELSE 'Standard'
    END AS ContentImpactLevel
FROM
    UserEngagementSummary UES
INNER JOIN
    PostDetailMetrics PDM ON UES.UserId = PDM.OwnerUserId
LEFT JOIN
    TagPerformance TP ON PDM.PostId = TP.PostId
WHERE
    UES.DaysSinceLastActivity < 90
    AND (PDM.LinkedPostCount > 0 OR PDM.DuplicatePostCount > 0)
    AND PDM.PostScore >= 0
    AND PDM.ViewCount > 1000
    AND UES.Location IS NOT NULL
ORDER BY
    Reputation DESC, EngagementIndex DESC, PostCreationDate DESC
LIMIT 10000;