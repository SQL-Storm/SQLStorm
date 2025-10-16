WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.UpVotes AS TotalUpVotesGiven,
        U.DownVotes AS TotalDownVotesGiven,
        (U.UpVotes - U.DownVotes) AS NetVotesGiven,
        COALESCE(SUM(P.Score), 0) AS TotalPostScoreOwned,
        COUNT(DISTINCT P.Id) AS PostsCount,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionsCount,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswersCount,
        RANK() OVER (ORDER BY U.Reputation DESC, (U.UpVotes - U.DownVotes) DESC) AS ReputationRank,
        NTILE(4) OVER (ORDER BY U.CreationDate ASC, U.Id ASC) AS UserAgeQuartile,
        CASE
            WHEN U.Reputation > 10000 THEN 'Elite'
            WHEN U.Reputation > 2000 THEN 'Experienced'
            WHEN U.Reputation > 500 THEN 'Contributor'
            ELSE 'Novice'
        END AS ReputationTier
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    WHERE
        U.LastAccessDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '2' YEAR)
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes
    HAVING
        COUNT(P.Id) > 5 OR U.Reputation > 1000
),
QuestionDetails AS (
    SELECT
        Q.Id AS QuestionId,
        Q.Title AS QuestionTitle,
        Q.CreationDate AS QuestionCreationDate,
        Q.OwnerUserId,
        Q.Score AS QuestionScore,
        Q.ViewCount,
        Q.AnswerCount,
        Q.FavoriteCount,
        Q.ClosedDate,
        Q.Tags,
        (SELECT COALESCE(AVG(A.Score), 0) FROM Posts A WHERE A.ParentId = Q.Id AND A.PostTypeId = 2) AS AvgAnswerScore,
        (SELECT COUNT(DISTINCT PH.UserId) FROM PostHistory PH WHERE PH.PostId = Q.Id AND PH.PostHistoryTypeId IN (4, 5, 6)) AS UniqueEditorsCount,
        COALESCE(
            (SELECT CRT_Sub.Name
             FROM PostHistory PH_Close_Sub
             JOIN CloseReasonTypes CRT_Sub ON CAST(PH_Close_Sub.Comment AS INTEGER) = CRT_Sub.Id
             WHERE PH_Close_Sub.PostId = Q.Id AND PH_Close_Sub.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105)
             ORDER BY PH_Close_Sub.CreationDate DESC FETCH FIRST 1 ROW ONLY), 'N/A'
        ) AS LatestCloseReason,
        (SELECT C_Sub.Text FROM Comments C_Sub WHERE C_Sub.PostId = Q.Id ORDER BY C_Sub.CreationDate DESC FETCH FIRST 1 ROW ONLY) AS LatestCommentText,
        SUM(CASE WHEN C.Score < 0 THEN 1 ELSE 0 END) AS NegativeCommentCount,
        COUNT(PL_Dup.RelatedPostId) AS DuplicateLinkCount
    FROM
        Posts Q
    LEFT JOIN
        Comments C ON Q.Id = C.PostId
    LEFT JOIN
        PostLinks PL_Dup ON Q.Id = PL_Dup.PostId AND PL_Dup.LinkTypeId = 3
    WHERE
        Q.PostTypeId = 1
    GROUP BY
        Q.Id, Q.Title, Q.CreationDate, Q.OwnerUserId, Q.Score, Q.ViewCount, Q.AnswerCount, Q.FavoriteCount, Q.ClosedDate, Q.Tags
),
TopAnswerPerQuestion AS (
    SELECT
        t.QuestionId,
        t.TopAnswerId,
        t.TopAnswerScore,
        t.TopAnswerCreationDate,
        t.TopAnswerOwnerId,
        t.SecondTopAnswerScore,
        t.ScoreDifferenceFromNext
    FROM (
        SELECT
            A.ParentId AS QuestionId,
            A.Id AS TopAnswerId,
            A.Score AS TopAnswerScore,
            A.CreationDate AS TopAnswerCreationDate,
            A.OwnerUserId AS TopAnswerOwnerId,
            LAG(A.Score, 1, 0) OVER (PARTITION BY A.ParentId ORDER BY A.Score DESC, A.CreationDate ASC) AS SecondTopAnswerScore,
            (A.Score - LAG(A.Score, 1, 0) OVER (PARTITION BY A.ParentId ORDER BY A.Score DESC, A.CreationDate ASC)) AS ScoreDifferenceFromNext,
            ROW_NUMBER() OVER (PARTITION BY A.ParentId ORDER BY A.Score DESC, A.CreationDate ASC) AS rn
        FROM
            Posts A
        WHERE
            A.PostTypeId = 2
    ) t
    WHERE t.rn = 1
),
HighlyVotedComments AS (
    SELECT
        C.PostId AS QuestionId,
        C.Text AS CommentText,
        C.Score AS CommentScore,
        C.UserId AS CommentOwnerId,
        C.CreationDate AS CommentCreationDate
    FROM
        Comments C
    WHERE
        C.Score > 5
        AND C.PostId IN (SELECT Id FROM Posts WHERE PostTypeId = 1)
),
FrequentBadges AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS GoldSilverBadgeCount,
        MAX(B.Date) AS LatestBadgeDate
    FROM
        Badges B
    WHERE
        B.Class IN (1, 2)
        AND B.Date >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1' YEAR)
    GROUP BY
        B.UserId
    HAVING
        COUNT(B.Id) >= 3
),
ModeratorActivity AS (
    SELECT
        PH.PostId,
        'Locked/Unlocked' AS ActionType,
        PH.CreationDate AS ActionDate,
        PH.UserId AS ModeratorUserId
    FROM PostHistory PH WHERE PH.PostHistoryTypeId IN (14, 15)
    UNION ALL
    SELECT
        PH.PostId,
        'Protected/Unprotected' AS ActionType,
        PH.CreationDate AS ActionDate,
        PH.UserId AS ModeratorUserId
    FROM PostHistory PH WHERE PH.PostHistoryTypeId IN (19, 20)
    UNION ALL
    SELECT
        PH.PostId,
        'Deleted/Undeleted' AS ActionType,
        PH.CreationDate AS ActionDate,
        PH.UserId AS ModeratorUserId
    FROM PostHistory PH WHERE PH.PostHistoryTypeId IN (12, 13)
)
SELECT
    QD.QuestionId,
    QD.QuestionTitle,
    QD.QuestionCreationDate,
    UA.DisplayName AS QuestionOwnerDisplayName,
    UA.Reputation AS QuestionOwnerReputation,
    QD.QuestionScore,
    QD.ViewCount,
    QD.AnswerCount,
    QD.FavoriteCount,
    QD.LatestCloseReason,
    QD.UniqueEditorsCount,
    QD.AvgAnswerScore,
    QD.NegativeCommentCount,
    QD.DuplicateLinkCount,
    TAPQ.TopAnswerScore,
    TAPQ.ScoreDifferenceFromNext,
    FB.GoldSilverBadgeCount AS OwnerGoldSilverBadges,
    COALESCE(HV.CommentText, 'No High Score Comment') AS CriticalCommentExcerpt,
    MOD_ACT.ActionType AS LatestModeratorAction,
    MOD_ACT.ActionDate AS LatestModeratorActionDate,
    (CAST(QD.QuestionScore AS DECIMAL) / NULLIF(QD.ViewCount, 0)) AS ScoreToViewRatio,
    (CAST(QD.FavoriteCount AS DECIMAL) / NULLIF(QD.ViewCount, 0)) AS FavoriteToViewRatio,
    (QD.QuestionScore + COALESCE(QD.AvgAnswerScore, 0) + COALESCE(QD.FavoriteCount, 0)) AS CombinedEngagementScore,
    CASE
        WHEN QD.ClosedDate IS NOT NULL AND QD.LatestCloseReason NOT LIKE '%Duplicate%' THEN 'Problematic (Closed Non-Duplicate)'
        WHEN QD.AnswerCount = 0 AND QD.ViewCount > 5000 THEN 'Unanswered Popular'
        WHEN QD.QuestionScore < 0 AND QD.ViewCount > 1000 THEN 'Controversial Low Score'
        WHEN QD.UniqueEditorsCount > 5 AND QD.QuestionScore > 50 THEN 'Highly Edited & Popular'
        WHEN TAPQ.ScoreDifferenceFromNext IS NOT NULL AND TAPQ.ScoreDifferenceFromNext > 50 THEN 'Dominant Answer'
        WHEN MOD_ACT.ActionType IS NOT NULL THEN 'Moderated Post'
        ELSE 'Standard'
    END AS QuestionCategory,
    UPPER(SUBSTRING(COALESCE(QD.QuestionTitle, '') FROM 1 FOR 1)) AS TitleFirstCharUpper,
    TRIM(REPLACE(REPLACE(COALESCE(QD.Tags, ''), '>', ' '), '<', ' ')) AS CleanedTags,
    COALESCE(UA.ReputationTier, 'Unknown') AS QuestionOwnerReputationTier,
    (TAPQ.TopAnswerId IS NULL AND QD.AnswerCount > 0) AS HasNoTopAnswerDespiteAnswers,
    (MOD_ACT.PostId IS NOT NULL AND MOD_ACT.ActionType = 'Deleted/Undeleted') AS WasDeletedOrUndeleted
FROM
    QuestionDetails QD
LEFT JOIN
    UserActivitySummary UA ON QD.OwnerUserId = UA.UserId
LEFT JOIN
    TopAnswerPerQuestion TAPQ ON QD.QuestionId = TAPQ.QuestionId
LEFT JOIN
    FrequentBadges FB ON QD.OwnerUserId = FB.UserId
LEFT JOIN LATERAL
    (
     SELECT
         MA.ActionType,
         MA.ActionDate,
         MA.PostId,
         MA.ModeratorUserId
     FROM ModeratorActivity MA
     WHERE MA.PostId = QD.QuestionId
     ORDER BY MA.ActionDate DESC
     FETCH FIRST 1 ROW ONLY
    ) MOD_ACT ON TRUE
LEFT JOIN LATERAL
    (
     SELECT HVC.CommentText, HVC.CommentOwnerId
     FROM HighlyVotedComments HVC
     WHERE HVC.QuestionId = QD.QuestionId
     ORDER BY HVC.CommentScore DESC
     FETCH FIRST 1 ROW ONLY
    ) HV ON TRUE
WHERE
    QD.ViewCount > 1000
    AND QD.QuestionCreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '3' YEAR)
    AND (QD.QuestionScore > 15 OR QD.AnswerCount > 7 OR QD.FavoriteCount > 3)
    AND (
        QD.LatestCloseReason NOT LIKE '%Duplicate%'
        OR QD.ClosedDate IS NULL
        OR QD.UniqueEditorsCount > 4
    )
    AND (
        UA.Reputation > 750
        OR QD.OwnerUserId IS NULL
    )
    AND (
        QD.Tags LIKE '%<sql>%'
        OR QD.Tags LIKE '%<database>%'
        OR QD.Tags LIKE '%<performance>%'
        OR QD.Tags LIKE '%<query-optimization>%'
    )
    AND (NOT (TAPQ.TopAnswerId IS NULL AND QD.AnswerCount > 0) OR QD.AnswerCount = 0)
    AND (QD.LatestCommentText IS NOT NULL OR HV.CommentText IS NOT NULL OR QD.NegativeCommentCount > 0)
ORDER BY
    CombinedEngagementScore DESC,
    QD.QuestionCreationDate DESC
FETCH FIRST 500 ROWS ONLY;