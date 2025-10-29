-- {"query": "1103.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3216} 

WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.LastAccessDate,
        U.UpVotes AS UserTotalUpVotes,
        U.DownVotes AS UserTotalDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT V.PostId) AS TotalVotedPosts,
        SUM(P.Score) AS SumPostScore,
        AVG(P.Score) AS AvgPostScore,
        MAX(P.LastActivityDate) AS LastPostActivity,
        CAST(U.UpVotes AS decimal) / NULLIF(U.UpVotes + U.DownVotes, 0) AS UserVoteRatio,
        MAX(CASE WHEN B.Name = 'Disciplined' THEN B.Date END) AS DisciplinedBadgeDate,
        MAX(CASE WHEN B.Name = 'Pundit' THEN B.Date END) AS PunditBadgeDate
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Votes AS V ON U.Id = V.UserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes
),
PostDetailsAndHistory AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.OwnerUserId,
        P.Title,
        P.Tags,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        COALESCE(MAX(CASE WHEN PH.PostHistoryTypeId IN (5,6) THEN PH.CreationDate END), P.LastEditDate, P.CreationDate) AS LastContentEditDate,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (5,6) THEN 1 END) AS EditCount,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.Id END) AS CloseCount,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.Id END) AS ReopenCount,
        CASE WHEN P.AcceptedAnswerId IS NOT NULL THEN TRUE ELSE FALSE END AS HasAcceptedAnswer,
        CASE WHEN P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2 THEN string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><') ELSE NULL END AS TagArray,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS DirectUpvoteCount,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DirectDownvoteCount,
        SUM(CASE WHEN V.VoteTypeId = 4 THEN 1 ELSE 0 END) AS DirectOffensiveVoteCount
    FROM Posts AS P
    INNER JOIN PostTypes AS PT ON P.PostTypeId = PT.Id
    LEFT JOIN PostHistory AS PH ON P.Id = PH.PostId
    LEFT JOIN Votes AS V ON P.Id = V.PostId AND V.VoteTypeId IN (2,3,4)
    GROUP BY P.Id, P.PostTypeId, PT.Name, P.OwnerUserId, P.Title, P.Tags, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.ClosedDate, P.AcceptedAnswerId, P.LastEditDate
),
CombinedPostData AS (
    SELECT
        PD.PostId,
        PD.PostTypeId,
        PD.PostTypeName,
        PD.OwnerUserId,
        UE.DisplayName AS OwnerDisplayName,
        UE.Reputation AS OwnerReputation,
        UE.UserTotalUpVotes AS OwnerTotalUpVotesGiven,
        UE.UserTotalDownVotes AS OwnerTotalDownVotesGiven,
        PD.Title,
        PD.Tags,
        PD.TagArray,
        PD.PostCreationDate,
        PD.PostScore,
        PD.ViewCount,
        PD.AnswerCount,
        PD.CommentCount,
        PD.FavoriteCount,
        PD.ClosedDate,
        PD.HasAcceptedAnswer,
        PD.LastContentEditDate,
        PD.EditCount,
        PD.CloseCount,
        PD.ReopenCount,
        COALESCE(PD.DirectUpvoteCount, 0) AS UpvoteCount,
        COALESCE(PD.DirectDownvoteCount, 0) AS DownvoteCount,
        COALESCE(PD.DirectOffensiveVoteCount, 0) AS OffensiveVoteCount,
        COALESCE(PD.DirectUpvoteCount, 0) + COALESCE(PD.DirectDownvoteCount, 0) AS TotalUpDownVotes,
        CAST(PD.FavoriteCount AS decimal) / NULLIF(PD.ViewCount, 0) AS FavoriteToViewRatio,
        CAST(PD.AnswerCount AS decimal) / NULLIF(PD.ViewCount, 0) AS AnswerToViewRatio,
        CAST(COALESCE(PD.DirectUpvoteCount, 0) AS decimal) / NULLIF(COALESCE(PD.DirectUpvoteCount, 0) + COALESCE(PD.DirectDownvoteCount, 0), 0) AS UpvoteRatio,
        CASE
            WHEN PD.PostScore >= 50 THEN 'Highly Scored'
            WHEN PD.PostScore >= 10 THEN 'Well Scored'
            WHEN PD.PostScore > 0 THEN 'Positively Scored'
            WHEN PD.PostScore = 0 THEN 'Neutral'
            WHEN PD.PostScore >= -5 THEN 'Slightly Negative'
            ELSE 'Highly Negative'
        END AS ScoreCategory,
        EXISTS (
            SELECT 1
            FROM PostHistory PH_close
            WHERE PH_close.PostId = PD.PostId
              AND PH_close.PostHistoryTypeId = 10
              AND COALESCE(PH_close.Comment, '') LIKE '101%'
        ) AS IsDuplicateClosed,
        (SELECT COUNT(B.Id) FROM Badges B WHERE B.UserId = PD.OwnerUserId AND B.Name = 'Great Answer' AND B.Class = 2) > 0 AS OwnerHasGreatAnswerBadgeSilver,
        UE.DisciplinedBadgeDate IS NOT NULL AS OwnerHasDisciplinedBadge,
        UE.PunditBadgeDate IS NOT NULL AS OwnerHasPunditBadge,
        -- Scalar subquery for average comment score on this post
        (SELECT AVG(C.Score) FROM Comments C WHERE C.PostId = PD.PostId) AS AvgCommentScore
    FROM PostDetailsAndHistory AS PD
    INNER JOIN UserEngagement AS UE ON PD.OwnerUserId = UE.UserId
),
RankedPostData AS (
    SELECT
        CPD.*,
        ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY PostScore DESC, ViewCount DESC) AS Rnk_OwnerPostScore,
        NTILE(4) OVER (ORDER BY PostScore DESC) AS Quartile_GlobalPostScore,
        LAG(PostCreationDate, 1, '1900-01-01'::timestamp) OVER (PARTITION BY OwnerUserId ORDER BY PostCreationDate) AS PreviousPostCreationDate,
        AVG(PostScore) OVER (PARTITION BY OwnerUserId) AS AvgScoreByOwner,
        MAX(PostScore) OVER (PARTITION BY OwnerUserId) AS MaxScoreByOwner,
        MIN(PostScore) OVER (PARTITION BY OwnerUserId) AS MinScoreByOwner,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY OwnerUserId) AS OwnerQuestionCount,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY OwnerUserId) AS OwnerAnswerCount,
        (SELECT PL.RelatedPostId FROM PostLinks PL WHERE PL.PostId = CPD.PostId AND PL.LinkTypeId = 3 ORDER BY PL.CreationDate DESC LIMIT 1) AS DuplicateOfPostId
    FROM CombinedPostData AS CPD
    WHERE CPD.OwnerUserId IS NOT NULL
),
HighlyEngagedTagUsers AS (
    SELECT
        T.TagName,
        RPD.OwnerUserId,
        COUNT(DISTINCT RPD.PostId) AS PostsInTagCount,
        SUM(RPD.PostScore) AS TagPostScoreSum,
        AVG(RPD.PostScore) AS TagPostScoreAvg,
        ROW_NUMBER() OVER (PARTITION BY T.TagName ORDER BY SUM(RPD.PostScore) DESC) AS Rnk_TagUserScore
    FROM RankedPostData AS RPD
    CROSS JOIN LATERAL UNNEST(RPD.TagArray) AS T(TagName)
    WHERE RPD.PostTypeId = 1 -- Only consider questions for tag engagement
    GROUP BY T.TagName, RPD.OwnerUserId
    HAVING COUNT(DISTINCT RPD.PostId) > 5
)
SELECT
    RPD.PostId,
    RPD.PostTypeName,
    RPD.OwnerDisplayName,
    RPD.OwnerReputation,
    RPD.Title,
    RPD.PostCreationDate,
    RPD.PostScore,
    RPD.ViewCount,
    RPD.FavoriteCount,
    RPD.AnswerCount,
    RPD.CommentCount,
    RPD.ClosedDate,
    RPD.EditCount,
    RPD.CloseCount,
    RPD.ReopenCount,
    RPD.UpvoteCount,
    RPD.DownvoteCount,
    RPD.OffensiveVoteCount,
    RPD.TotalUpDownVotes,
    RPD.FavoriteToViewRatio,
    RPD.UpvoteRatio,
    RPD.ScoreCategory,
    RPD.IsDuplicateClosed,
    RPD.OwnerHasGreatAnswerBadgeSilver,
    RPD.OwnerHasDisciplinedBadge,
    RPD.OwnerHasPunditBadge,
    RPD.AvgCommentScore,
    RPD.Rnk_OwnerPostScore,
    RPD.Quartile_GlobalPostScore,
    RPD.PreviousPostCreationDate,
    RPD.AvgScoreByOwner,
    RPD.MaxScoreByOwner,
    RPD.MinScoreByOwner,
    RPD.OwnerQuestionCount,
    RPD.OwnerAnswerCount,
    T.TagName AS PrimaryTag,
    DUPL.Title AS DuplicateOfPostTitle,
    DUPL.OwnerDisplayName AS DuplicateOfPostOwner,
    COALESCE(HETU.PostsInTagCount, 0) AS OwnerPostsInPrimaryTagCount,
    COALESCE(HETU.TagPostScoreAvg, 0) AS OwnerAvgScoreInPrimaryTag,
    EXTRACT(EPOCH FROM (NOW() - RPD.LastContentEditDate)) / (60 * 60 * 24) AS DaysSinceLastEdit,
    AGE(RPD.LastContentEditDate, RPD.PostCreationDate) AS TimeToFirstEdit,
    CASE
        WHEN RPD.OffensiveVoteCount > 0 THEN 'Flagged Offensive'
        WHEN RPD.CloseCount > 0 AND RPD.ReopenCount > 0 THEN 'Closed & Reopened'
        WHEN RPD.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN RPD.PostScore < 0 AND RPD.DownvoteCount > RPD.UpvoteCount AND RPD.TotalUpDownVotes >= 5 THEN 'Controversial Negative'
        WHEN RPD.PostScore > 100 AND RPD.FavoriteCount > 100 AND RPD.ViewCount > 10000 THEN 'Highly Valued & Popular'
        WHEN RPD.EditCount > 5 AND RPD.PostScore < 10 THEN 'Heavily Edited Low Score'
        ELSE 'Normal'
    END AS PostStatusDetail,
    COALESCE(U_Owner.Location, 'Unknown Location') AS OwnerLocation,
    LOWER(COALESCE(U_Owner.AboutMe, '')) LIKE '%contributing developer%' OR LOWER(COALESCE(U_Owner.AboutMe, '')) LIKE '%open source%' AS OwnerLikelyDeveloperOrOSSContributor,
    NULLIF(U_Owner.WebsiteUrl, '') IS NOT NULL AS OwnerHasWebsite,
    (SELECT COUNT(DISTINCT V.UserId) FROM Votes V WHERE V.PostId = RPD.PostId AND V.VoteTypeId = 5) AS NumberOfFavoriteUsers
FROM RankedPostData AS RPD
LEFT JOIN Users AS U_Owner ON RPD.OwnerUserId = U_Owner.Id
LEFT JOIN Posts AS DUPL ON RPD.DuplicateOfPostId = DUPL.Id
LEFT JOIN Tags AS T ON T.TagName = RPD.TagArray[1]
LEFT JOIN HighlyEngagedTagUsers AS HETU ON RPD.OwnerUserId = HETU.OwnerUserId AND T.TagName = HETU.TagName
WHERE
    RPD.PostTypeId IN (1, 2)
    AND RPD.PostCreationDate >= (NOW() - INTERVAL '3 year')
    AND RPD.ViewCount > 50
    AND RPD.PostScore IS NOT NULL
    AND (RPD.OwnerReputation > 2000 OR RPD.TotalUpDownVotes > 5)
ORDER BY
    RPD.OwnerReputation DESC,
    RPD.PostScore DESC,
    RPD.LastContentEditDate DESC
LIMIT 5000;
