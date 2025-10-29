-- {"query": "1419.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3316}
WITH UserOverallStats AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        COUNT(CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestionsOwned,
        COUNT(CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswersOwned,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.ViewCount ELSE 0 END) AS TotalQuestionViews,
        MAX(P.LastActivityDate) AS LastPostActivity,
        COUNT(DISTINCT CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadgesCount,
        COUNT(DISTINCT CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadgesCount,
        COUNT(DISTINCT CASE WHEN B.Class = 3 THEN B.Id END) AS BronzeBadgesCount,
        AVG(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE NULL END) AS AvgAnswerScore
    FROM
        Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.Views, U.UpVotes, U.DownVotes
),
QuestionDetailedMetrics AS (
    SELECT
        Q.Id AS QuestionId,
        Q.AcceptedAnswerId,
        Q.CreationDate AS QuestionCreationDate,
        Q.ViewCount,
        Q.Score AS QuestionScore,
        Q.AnswerCount,
        Q.CommentCount AS InitialCommentCount,
        Q.FavoriteCount,
        Q.Title AS QuestionTitle,
        Q.Body AS QuestionBody,
        Q.Tags AS RawTags,
        COALESCE(Q.LastEditDate, Q.CreationDate) AS LastEditOrCreationDate,
        CASE WHEN Q.Tags IS NOT NULL AND Q.Tags <> '' THEN
            -- Attempt to produce an array-like result in dialects that support regexp functions.
            -- If regexp_split_to_array is not available in a target dialect, this expression may need adapting,
            -- but we avoid Postgres-specific empty-array literal problems by guarding empty string.
            regexp_split_to_array(regexp_replace(Q.Tags, '^<|>$', ''), '><')
        ELSE NULL END AS ParsedTags,
        (SELECT MAX(C.Score) FROM Comments C WHERE C.PostId = Q.Id) AS MaxCommentScore,
        (SELECT COUNT(DISTINCT C.UserId) FROM Comments C WHERE C.PostId = Q.Id AND C.UserId IS NOT NULL) AS UniqueCommenters,
        (SELECT SUM(V.BountyAmount) FROM Votes V WHERE V.PostId = Q.Id AND V.VoteTypeId = 8) AS TotalBountyAmount,
        COUNT(DISTINCT CASE WHEN PL.LinkTypeId = 3 THEN PL.RelatedPostId END) AS DuplicateLinkCount,
        COUNT(DISTINCT CASE WHEN PL.LinkTypeId = 1 THEN PL.RelatedPostId END) AS LinkedPostCount
    FROM
        Posts Q
    LEFT JOIN PostLinks PL ON Q.Id = PL.PostId
    WHERE
        Q.PostTypeId = 1
    GROUP BY
        Q.Id, Q.AcceptedAnswerId, Q.CreationDate, Q.ViewCount, Q.Score, Q.AnswerCount, Q.CommentCount, Q.FavoriteCount, Q.Title, Q.Body, Q.Tags, Q.LastEditDate
),
PostLifecycleEvents AS (
    SELECT
        PH.PostId,
        PH.CreationDate AS EventDate,
        PH.PostHistoryTypeId,
        PHT.Name AS EventTypeName
    FROM
        PostHistory PH
    JOIN PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
    WHERE
        PH.PostHistoryTypeId IN (10, 11)
),
ClosedDurationAnalysis AS (
    SELECT
        ple.PostId,
        MIN(CASE WHEN ple.PostHistoryTypeId = 10 THEN ple.EventDate END) AS FirstClosedDate,
        MAX(CASE WHEN next_reopen.PostHistoryTypeId = 11 THEN next_reopen.EventDate END) AS LastReopenedDate,
        SUM(
            EXTRACT(EPOCH FROM (
                COALESCE(
                    (SELECT MIN(pr.EventDate) FROM PostLifecycleEvents pr WHERE pr.PostId = ple.PostId AND pr.PostHistoryTypeId = 11 AND pr.EventDate > ple.EventDate),
                    TIMESTAMP '2024-10-01 12:34:56'
                ) - ple.EventDate
            ))
        ) FILTER (WHERE ple.PostHistoryTypeId = 10) AS TotalSecondsClosed_Estimate,
        MAX(CASE WHEN ple.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) = 1 AS WasEverClosed,
        MAX(CASE WHEN ple.PostHistoryTypeId = 10 AND (
            (SELECT MIN(pr.EventDate) FROM PostLifecycleEvents pr WHERE pr.PostId = ple.PostId AND pr.PostHistoryTypeId = 11 AND pr.EventDate > ple.EventDate) IS NULL
        ) THEN 1 ELSE 0 END) = 1 AS IsCurrentlyClosed
    FROM
        PostLifecycleEvents ple
    LEFT JOIN PostLifecycleEvents next_reopen ON next_reopen.PostId = ple.PostId
        AND next_reopen.PostHistoryTypeId = 11
        AND next_reopen.EventDate = (
            SELECT MIN(pr.EventDate)
            FROM PostLifecycleEvents pr
            WHERE pr.PostId = ple.PostId
              AND pr.PostHistoryTypeId = 11
              AND pr.EventDate > ple.EventDate
        )
    GROUP BY ple.PostId
    HAVING MAX(CASE WHEN ple.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) = 1
),
BaseQuestionData AS (
    SELECT
        Q.QuestionId,
        Q.QuestionTitle,
        Q.QuestionCreationDate,
        Q.QuestionScore,
        Q.ViewCount,
        Q.AnswerCount,
        Q.FavoriteCount,
        UOS.UserId AS OwnerUserId,
        UOS.DisplayName AS OwnerDisplayName,
        UOS.Reputation AS OwnerReputation,
        UOS.TotalQuestionsOwned AS OwnerTotalQuestions,
        UOS.GoldBadgesCount AS OwnerGoldBadges,
        Q.MaxCommentScore,
        Q.UniqueCommenters,
        Q.TotalBountyAmount,
        Q.DuplicateLinkCount,
        Q.LinkedPostCount,
        CDA.WasEverClosed,
        CDA.IsCurrentlyClosed,
        CDA.TotalSecondsClosed_Estimate,
        CDA.FirstClosedDate,
        CDA.LastReopenedDate,
        COALESCE(AA.Score, 0) AS AcceptedAnswerScore,
        AA_UOS.DisplayName AS AcceptedAnswerOwnerDisplayName,
        AA_UOS.Reputation AS AcceptedAnswerOwnerReputation,
        Q.ParsedTags,
        UOS.UserCreationDate,
        UOS.TotalPostScore,
        Q.RawTags,
        P_Q.LastEditDate,
        COUNT(DISTINCT A.Id) AS TotalAnswersFound,
        AVG(A.Score) AS AverageAnswerScoreForQuestion,
        MAX(A.CreationDate) AS LatestAnswerDateForQuestion
    FROM
        Posts P_Q
    JOIN QuestionDetailedMetrics Q ON P_Q.Id = Q.QuestionId
    LEFT JOIN UserOverallStats UOS ON P_Q.OwnerUserId = UOS.UserId
    LEFT JOIN ClosedDurationAnalysis CDA ON Q.QuestionId = CDA.PostId
    LEFT JOIN Posts A ON A.ParentId = Q.QuestionId AND A.PostTypeId = 2
    LEFT JOIN Posts AA ON Q.AcceptedAnswerId = AA.Id AND AA.PostTypeId = 2
    LEFT JOIN UserOverallStats AA_UOS ON AA.OwnerUserId = AA_UOS.UserId
    WHERE
        P_Q.PostTypeId = 1
    GROUP BY
        Q.QuestionId, Q.QuestionTitle, Q.QuestionCreationDate, Q.QuestionScore, Q.ViewCount, Q.AnswerCount, Q.FavoriteCount,
        UOS.UserId, UOS.DisplayName, UOS.Reputation, UOS.TotalQuestionsOwned, UOS.GoldBadgesCount, Q.MaxCommentScore, Q.UniqueCommenters,
        Q.TotalBountyAmount, Q.DuplicateLinkCount, Q.LinkedPostCount, CDA.WasEverClosed, CDA.IsCurrentlyClosed,
        CDA.TotalSecondsClosed_Estimate, CDA.FirstClosedDate, CDA.LastReopenedDate, AA.Score, AA_UOS.DisplayName, AA_UOS.Reputation,
        Q.ParsedTags, UOS.UserCreationDate, UOS.TotalPostScore, Q.RawTags, P_Q.LastEditDate
),
RankedQuestions AS (
    SELECT
        bq.*,
        ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY QuestionScore DESC, ViewCount DESC) AS RankByOwnerScore,
        NTILE(10) OVER (ORDER BY QuestionCreationDate DESC) AS CreationDateDecile,
        LAG(QuestionScore, 1, 0) OVER (PARTITION BY OwnerUserId ORDER BY QuestionCreationDate) AS PrevQuestionScoreByOwner
    FROM
        BaseQuestionData bq
)
SELECT
    RQ.QuestionId,
    RQ.QuestionTitle,
    RQ.QuestionCreationDate,
    RQ.QuestionScore,
    RQ.ViewCount,
    RQ.AnswerCount,
    RQ.FavoriteCount,
    RQ.OwnerDisplayName,
    RQ.OwnerReputation,
    RQ.OwnerTotalQuestions,
    RQ.OwnerGoldBadges,
    RQ.MaxCommentScore,
    RQ.UniqueCommenters,
    RQ.TotalBountyAmount,
    RQ.DuplicateLinkCount,
    RQ.LinkedPostCount,
    COALESCE(RQ.WasEverClosed, FALSE) AS WasQuestionEverClosed,
    COALESCE(RQ.IsCurrentlyClosed, FALSE) AS IsQuestionCurrentlyClosed,
    RQ.TotalSecondsClosed_Estimate,
    RQ.FirstClosedDate,
    RQ.LastReopenedDate,
    RQ.AcceptedAnswerScore,
    RQ.AcceptedAnswerOwnerDisplayName,
    RQ.AcceptedAnswerOwnerReputation,
    (SELECT COUNT(DISTINCT V.UserId) FROM Votes V WHERE V.PostId = RQ.QuestionId AND V.VoteTypeId = 2) AS UniqueUpvotersCount,
    (SELECT COUNT(*) FROM Comments C WHERE C.PostId = RQ.QuestionId AND CHAR_LENGTH(C.Text) > 100 AND C.Score >= 5) AS HighQualityCommentsCount,
    CASE
        WHEN RQ.QuestionScore >= 50 AND RQ.ViewCount >= 1000 AND RQ.AnswerCount >= 5 THEN 'HotTopic'
        WHEN RQ.QuestionScore >= 10 AND RQ.AnswerCount >= 2 THEN 'Engaging'
        WHEN RQ.FavoriteCount > 0 AND RQ.QuestionScore > 0 THEN 'Interesting'
        ELSE 'Regular'
    END AS QuestionCategory,
    CASE WHEN RQ.ParsedTags IS NOT NULL THEN array_to_string(RQ.ParsedTags, ',') ELSE NULL END AS FormattedTags,
    RQ.RankByOwnerScore,
    RQ.CreationDateDecile,
    RQ.PrevQuestionScoreByOwner,
    RQ.TotalPostScore * 1.0 / NULLIF(EXTRACT(DAY FROM (TIMESTAMP '2024-10-01 12:34:56' - RQ.UserCreationDate)), 0) AS OwnerAvgDailyScore,
    CONCAT_WS(' | ',
        CASE WHEN RQ.QuestionTitle LIKE '%SQL%' THEN 'SQL_Related' ELSE NULL END,
        CASE WHEN RQ.QuestionTitle LIKE '%Python%' THEN 'Python_Related' ELSE NULL END,
        CASE WHEN RQ.RawTags ILIKE '%<performance>%' THEN 'PerformanceTag' ELSE NULL END,
        COALESCE(REPLACE(SUBSTRING(RQ.QuestionTitle FROM 1 FOR 20), ' ', '_'), 'NoTitlePrefix')
    ) AS DerivedAttributesString
FROM
    RankedQuestions RQ
WHERE
    RQ.QuestionCreationDate >= DATE '2020-01-01'
    AND RQ.ViewCount >= 50
    AND (RQ.AnswerCount > 0 OR RQ.FavoriteCount > 0)
    AND (RQ.OwnerReputation > 5000 OR COALESCE(RQ.OwnerGoldBadges, 0) > 0)
    AND (RQ.RawTags LIKE '%<sql>%' OR RQ.RawTags LIKE '%<database>%')
    AND RQ.QuestionTitle IS NOT NULL AND CHAR_LENGTH(TRIM(RQ.QuestionTitle)) > 10
    AND (COALESCE(RQ.AverageAnswerScoreForQuestion, 0) > 2 OR COALESCE(RQ.IsCurrentlyClosed, FALSE) IS FALSE)
ORDER BY
    RQ.OwnerReputation DESC, RQ.QuestionScore DESC, RQ.ViewCount DESC
LIMIT 1000;