-- {"query": "1600.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2735}
WITH UserActivity AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.LastAccessDate,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        (SELECT COUNT(B.Id) FROM Badges B WHERE B.UserId = U.Id AND B.Class = 1) AS GoldBadges,
        (SELECT MAX(P.CreationDate) FROM Posts P WHERE P.OwnerUserId = U.Id) AS LastPostDate,
        (SELECT COUNT(DISTINCT PH.PostId) FROM PostHistory PH WHERE PH.UserId = U.Id AND PH.PostHistoryTypeId IN (4,5,6,9)) AS EditedPostsCount
    FROM
        Users U
    WHERE
        U.Reputation >= 1000
        AND U.LastAccessDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6 months')
),
PostEditHistoryDetails AS (
    SELECT
        PH.PostId,
        PH.PostHistoryTypeId,
        PHT.Name AS HistoryTypeName,
        PH.CreationDate AS EditDate,
        PH.UserId AS EditorUserId,
        PH.Comment,
        LAG(PH.CreationDate, 1, PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PreviousEditDate,
        (PH.CreationDate - LAG(PH.CreationDate, 1, PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate)) AS TimeSincePreviousEdit
    FROM
        PostHistory PH
    JOIN
        PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
    WHERE
        PH.PostHistoryTypeId IN (5, 8)
),
PostEditAggregates AS (
    SELECT
        PostId,
        COUNT(CASE WHEN PostHistoryTypeId = 5 THEN 1 END) AS BodyEditCount,
        COUNT(CASE WHEN PostHistoryTypeId = 8 THEN 1 END) AS RollbackCount,
        MAX(EditDate) AS LastBodyEditDate,
        SUM(EXTRACT(EPOCH FROM TimeSincePreviousEdit)) AS TotalEditTimeLagSeconds,
        AVG(CASE WHEN TimeSincePreviousEdit > INTERVAL '0 second' THEN EXTRACT(EPOCH FROM TimeSincePreviousEdit) END) AS AvgTimeBetweenBodyEdits
    FROM
        PostEditHistoryDetails
    GROUP BY
        PostId
),
LinkedPostAnalysis AS (
    SELECT
        PL.PostId,
        COUNT(DISTINCT PL.RelatedPostId) AS LinkedPostCount,
        SUM(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateLinkCount
    FROM
        PostLinks PL
    WHERE
        PL.LinkTypeId IN (1, 3)
    GROUP BY
        PL.PostId
),
PostStats AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.Title,
        P.Tags,
        P.AcceptedAnswerId,
        COALESCE(P.ClosedDate, CAST('1900-01-01' AS TIMESTAMP)) AS ClosedDate,
        CASE
            WHEN P.PostTypeId = 1 AND P.FavoriteCount >= 50 AND P.ViewCount >= 1000 THEN 'High Interest Question'
            WHEN P.PostTypeId = 1 AND P.Score >= 100 AND P.AnswerCount > 0 THEN 'Highly Rated Question with Answers'
            WHEN P.PostTypeId = 2 AND P.AcceptedAnswerId IS NOT NULL THEN 'Accepted Answer'
            WHEN P.PostTypeId = 2 AND P.Score >= 50 AND P.ParentId IS NOT NULL THEN 'Highly Rated Answer'
            ELSE 'Other Post'
        END AS PostCategory,
        (SELECT COUNT(DISTINCT C.Id) FROM Comments C WHERE C.PostId = P.Id AND C.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '3 months')) AS RecentCommentCount,
        (SELECT SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) FROM Votes V WHERE V.PostId = P.Id) AS UpVoteCount,
        (SELECT SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) FROM Votes V WHERE V.PostId = P.Id) AS DownVoteCount,
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate DESC) AS PostTypeScoreRank,
        CASE
            WHEN P.Tags IS NULL THEN 0
            ELSE ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags)-2), '><'), 1)
        END AS TagCount,
        PEA.BodyEditCount,
        PEA.RollbackCount,
        PEA.LastBodyEditDate,
        PEA.TotalEditTimeLagSeconds,
        PEA.AvgTimeBetweenBodyEdits,
        LPA.LinkedPostCount,
        LPA.DuplicateLinkCount
    FROM
        Posts P
    LEFT JOIN PostEditAggregates PEA ON P.Id = PEA.PostId
    LEFT JOIN LinkedPostAnalysis LPA ON P.Id = LPA.PostId
    WHERE
        P.PostTypeId IN (1, 2)
        AND P.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '2 years')
)
SELECT
    UA.UserId,
    UA.DisplayName,
    UA.Reputation,
    UA.GoldBadges,
    UA.EditedPostsCount,
    COALESCE((UA.UserUpVotes * 0.5 + UA.UserDownVotes * -0.2 + UA.UserViews * 0.01 + UA.GoldBadges * 10), 0) AS UserEngagementScore,
    COUNT(DISTINCT PS_Q.PostId) AS TotalQuestionsPosted,
    SUM(CASE WHEN PS_Q.PostCategory = 'High Interest Question' THEN 1 ELSE 0 END) AS HighInterestQuestions,
    AVG(PS_Q.PostScore) AS AvgQuestionScore,
    SUM(CASE WHEN PS_Q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswers,
    COUNT(DISTINCT PS_A.PostId) AS TotalAnswersPosted,
    SUM(CASE WHEN PS_A.PostCategory = 'Accepted Answer' THEN 1 ELSE 0 END) AS AcceptedAnswersCount,
    AVG(PS_A.PostScore) AS AvgAnswerScore,
    COUNT(DISTINCT C.Id) AS UserCommentCount,
    SUM(COALESCE(PS_Q.BodyEditCount, 0)) + SUM(COALESCE(PS_A.BodyEditCount, 0)) AS TotalBodyEditsByUserPosts,
    SUM(COALESCE(PS_Q.RollbackCount, 0)) + SUM(COALESCE(PS_A.RollbackCount, 0)) AS TotalRollbacksByUserPosts,
    AVG(CASE WHEN PS_Q.PostId IS NOT NULL THEN PS_Q.AvgTimeBetweenBodyEdits WHEN PS_A.PostId IS NOT NULL THEN PS_A.AvgTimeBetweenBodyEdits ELSE NULL END) AS OverallAvgTimeBetweenEditsSeconds,
    SUM(COALESCE(PS_Q.LinkedPostCount, 0)) + SUM(COALESCE(PS_A.LinkedPostCount, 0)) AS TotalLinkedPosts,
    SUM(COALESCE(PS_Q.DuplicateLinkCount, 0)) + SUM(COALESCE(PS_A.DuplicateLinkCount, 0)) AS TotalDuplicateLinks,
    AVG(
        CASE
            WHEN PS_Q.PostId IS NOT NULL THEN
                (PS_Q.PostScore * 1.0 + COALESCE(PS_Q.FavoriteCount, 0) * 2 + COALESCE(PS_Q.AnswerCount, 0) * 0.5)
                / NULLIF(PS_Q.ViewCount, 0) * 100
            WHEN PS_A.PostId IS NOT NULL THEN
                (PS_A.PostScore * 1.0 + CASE WHEN PS_A.PostCategory = 'Accepted Answer' THEN 5 ELSE 0 END)
                / NULLIF(PS_A.CommentCount + COALESCE(PS_A.RecentCommentCount, 0) + 1, 0)
            ELSE NULL
        END
    ) AS AvgCalculatedPostQuality,
    RANK() OVER (ORDER BY SUM(COALESCE(PS_Q.PostScore, 0) + COALESCE(PS_A.PostScore, 0)) DESC) AS UserOverallScoreRank,
    SUBSTRING(
        MAX(CASE WHEN PS_Q.PostTypeScoreRank = 1 THEN PS_Q.Tags END)
        FROM 2 FOR POSITION('><' IN COALESCE(MAX(CASE WHEN PS_Q.PostTypeScoreRank = 1 THEN PS_Q.Tags END), '') || '><') - 2
    ) AS TopQuestionFirstTag
FROM
    UserActivity UA
LEFT JOIN
    PostStats PS_Q ON UA.UserId = PS_Q.OwnerUserId AND PS_Q.PostTypeId = 1
LEFT JOIN
    PostStats PS_A ON UA.UserId = PS_A.OwnerUserId AND PS_A.PostTypeId = 2
LEFT JOIN
    Comments C ON UA.UserId = C.UserId AND C.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '2 years')
GROUP BY
    UA.UserId,
    UA.DisplayName,
    UA.Reputation,
    UA.GoldBadges,
    UA.EditedPostsCount,
    UA.UserUpVotes,
    UA.UserDownVotes,
    UA.UserViews
HAVING
    COUNT(DISTINCT PS_Q.PostId) > 0 OR COUNT(DISTINCT PS_A.PostId) > 0
ORDER BY
    UserEngagementScore DESC,
    AvgCalculatedPostQuality DESC
LIMIT 100;