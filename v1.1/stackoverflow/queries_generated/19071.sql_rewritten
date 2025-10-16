-- {"query": "19071.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1932} 
WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT V.Id) AS TotalVotes,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE 0 END) AS TotalAnswerScore,
        MAX(P.CreationDate) AS LatestPostDate,
        MIN(P.CreationDate) AS EarliestPostDate,
        MAX(C.CreationDate) AS LatestCommentDate,
        MAX(B.Date) AS LatestBadgeDate,
        DENSE_RANK() OVER (ORDER BY U.Reputation DESC, U.CreationDate ASC) AS ReputationRank
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostTagStats AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.Title,
        P.Tags,
        P.OwnerUserId,
        P.AcceptedAnswerId,
        P.ParentId,
        P.LastEditDate,
        P.LastActivityDate,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        P.CommunityOwnedDate,
        SUBSTRING(P.Tags, 2, POSITION('>' IN P.Tags) - 2) AS PrimaryTag,
        LENGTH(P.Tags) - LENGTH(REPLACE(P.Tags, '><', '')) + 1 AS TagCount,
        EXTRACT(EPOCH FROM (P.LastActivityDate - P.CreationDate)) / 3600 AS HoursSinceCreationToLastActivity,
        (CASE WHEN P.AnswerCount > 0 THEN CAST(P.CommentCount AS NUMERIC) / P.AnswerCount ELSE CAST(P.CommentCount AS NUMERIC) END) AS CommentToAnswerRatio,
        COUNT(DISTINCT PH.Id) AS RevisionCount,
        COUNT(DISTINCT PH.UserId) AS DistinctEditorCount
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId AND PH.PostHistoryTypeId IN (4,5,6,8,9)
    WHERE P.PostTypeId = 1
    GROUP BY
        P.Id, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.Title, P.Tags,
        P.OwnerUserId, P.AcceptedAnswerId, P.ParentId, P.LastEditDate, P.LastActivityDate,
        P.AnswerCount, P.CommentCount, P.FavoriteCount, P.ClosedDate, P.CommunityOwnedDate
),
PostLinkAndVoteAgg AS (
    SELECT
        P.Id AS PostId,
        COUNT(DISTINCT PL.Id) AS LinkedPostsCount,
        COUNT(DISTINCT CASE WHEN LT.Name = 'Duplicate' THEN PL.RelatedPostId END) AS DuplicatePostsCount,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteCountOnPost,
        SUM(CASE WHEN V.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS TotalVotesReceived,
        (SELECT MAX(U2.Reputation) FROM Users U2 JOIN Votes V2 ON U2.Id = V2.UserId WHERE V2.PostId = P.Id AND U2.Reputation > 1000) AS MaxReputationVoter
    FROM Posts P
    LEFT JOIN PostLinks PL ON P.Id = PL.PostId
    LEFT JOIN LinkTypes LT ON PL.LinkTypeId = LT.Id
    LEFT JOIN Votes V ON P.Id = V.PostId
    WHERE P.PostTypeId = 1
    GROUP BY P.Id
)
SELECT
    PTS.PostId,
    PTS.Title,
    UAS.DisplayName AS OwnerDisplayName,
    UAS.Reputation AS OwnerReputation,
    PTS.PostCreationDate,
    PTS.LastActivityDate,
    PTS.PostScore,
    PTS.ViewCount,
    PTS.AnswerCount,
    PTS.CommentCount,
    PLVA.FavoriteCountOnPost,
    PTS.PrimaryTag,
    PTS.TagCount,
    PTS.RevisionCount,
    PTS.DistinctEditorCount,
    PLVA.LinkedPostsCount,
    PLVA.DuplicatePostsCount,
    PLVA.UpVotesReceived,
    PLVA.DownVotesReceived,
    PLVA.MaxReputationVoter,
    COALESCE(CAST(PLVA.DownVotesReceived AS NUMERIC) * 0.5 + PTS.CommentToAnswerRatio * 2 + PTS.DistinctEditorCount * 0.75, 0) AS ControversyScore,
    RANK() OVER (PARTITION BY (UAS.Reputation / 10000) ORDER BY COALESCE(CAST(PLVA.DownVotesReceived AS NUMERIC) * 0.5 + PTS.CommentToAnswerRatio * 2 + PTS.DistinctEditorCount * 0.75, 0) DESC, PTS.PostScore DESC) AS RankByControversy,
    CASE
        WHEN PTS.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN PTS.AcceptedAnswerId IS NOT NULL AND PTS.AnswerCount > 0 THEN 'Answered & Accepted'
        WHEN PTS.AnswerCount > 0 AND PTS.PostScore > 50 THEN 'Answered & Highly Rated'
        WHEN PTS.LastActivityDate < cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '6 months' THEN 'Stale'
        WHEN PTS.OwnerUserId IS NULL THEN 'Community Post'
        ELSE 'Active'
    END AS PostStatus,
    UPPER(LEFT(COALESCE(PTS.PrimaryTag, 'NOTAG'), 3)) || LPAD(CAST(COALESCE(PTS.TagCount, 0) AS VARCHAR), 2, '0') AS TagPrefixCode,
    (
        SELECT COALESCE(AVG(Ans.Score), 0)
        FROM Posts Ans
        JOIN Users AnsweringUser ON Ans.OwnerUserId = AnsweringUser.Id
        WHERE Ans.ParentId = PTS.PostId
        AND AnsweringUser.Reputation > 5000
    ) AS AvgHighRepAnswerScore
FROM PostTagStats PTS
LEFT JOIN UserActivitySummary UAS ON PTS.OwnerUserId = UAS.UserId
LEFT JOIN PostLinkAndVoteAgg PLVA ON PTS.PostId = PLVA.PostId
WHERE
    PTS.PostScore > 10
    AND PTS.ViewCount > 1000
    AND PTS.PostCreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '5 year'
    AND (
        PTS.Title LIKE '%performance%' OR PTS.Title LIKE '%optimization%' OR PTS.Title LIKE '%benchmark%'
    )
    AND (
        PTS.AcceptedAnswerId IS NULL
        OR NOT EXISTS (SELECT 1 FROM Posts A WHERE A.Id = PTS.AcceptedAnswerId AND A.Score < 0)
    )
    AND (
        (UAS.Reputation IS NOT NULL AND UAS.Reputation > 50000 AND UAS.TotalPosts > 100)
        OR
        (PLVA.DownVotesReceived IS NOT NULL AND PLVA.DownVotesReceived > 5 AND PLVA.LinkedPostsCount > 0)
        OR
        (PTS.RevisionCount > 3 AND PTS.DistinctEditorCount > 1)
    )
ORDER BY
    ControversyScore DESC,
    RankByControversy ASC,
    PTS.PostScore DESC
LIMIT 1000;