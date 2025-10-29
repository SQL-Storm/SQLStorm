WITH UserAnswerSummary AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS TotalAnswers,
        SUM(p.Score) AS TotalAnswerScore,
        AVG(p.Score) AS AverageAnswerScore,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesOnAnswers,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesOnAnswers,
        MIN(p.CreationDate) AS FirstAnswerDate,
        MAX(p.CreationDate) AS LastAnswerDate
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    WHERE p.PostTypeId = 2
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserPostEditActivity AS (
    SELECT
        ph.PostId,
        p.OwnerUserId AS PostOwnerUserId,
        SUM(CASE WHEN ph.UserId = p.OwnerUserId AND ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS SelfEditsOnOwnPosts,
        SUM(CASE WHEN ph.UserId <> p.OwnerUserId AND ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS OtherUserEditsOnOwnPosts,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS OwnPostClosedEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS OwnPostReopenedEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS OwnPostDeletedEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId = 13 THEN 1 ELSE 0 END) AS OwnPostUndeletedEvents
    FROM PostHistory ph
    JOIN Posts p ON ph.PostId = p.Id
    WHERE p.OwnerUserId IS NOT NULL
      AND ph.PostHistoryTypeId IN (4, 5, 6, 10, 11, 12, 13)
    GROUP BY ph.PostId, p.OwnerUserId
),
AggregatedUserEditActivity AS (
    SELECT
        upa.PostOwnerUserId AS UserId,
        SUM(upa.SelfEditsOnOwnPosts) AS TotalSelfEditsOnOwnPosts,
        SUM(upa.OtherUserEditsOnOwnPosts) AS TotalOtherUserEditsOnOwnPosts,
        SUM(upa.OwnPostClosedEvents) AS TotalOwnPostsClosed,
        SUM(upa.OwnPostReopenedEvents) AS TotalOwnPostsReopened,
        SUM(upa.OwnPostDeletedEvents) AS TotalOwnPostsDeleted,
        SUM(upa.OwnPostUndeletedEvents) AS TotalOwnPostsUndeleted
    FROM UserPostEditActivity upa
    GROUP BY upa.PostOwnerUserId
),
UserCommentInteraction AS (
    SELECT
        c.UserId,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        SUM(c.Score) AS TotalCommentScore,
        COUNT(DISTINCT CASE WHEN EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = c.PostId AND v.VoteTypeId = 3) THEN c.PostId ELSE NULL END) AS CommentsOnDownvotedPosts,
        COUNT(DISTINCT CASE WHEN p.OwnerUserId = c.UserId THEN c.PostId ELSE NULL END) AS CommentsOnOwnPosts
    FROM Comments c
    LEFT JOIN Posts p ON c.PostId = p.Id
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UserTopAnswerTags AS (
    SELECT
        p.OwnerUserId AS UserId,
        LOWER(TRIM(tag_unnested.tag_name)) AS TagName,
        COUNT(p.Id) AS AnswerCountForTag,
        SUM(p.Score) AS AnswerScoreForTag
    FROM Posts p,
    LATERAL (SELECT UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')) AS tag_name) AS tag_unnested
    WHERE p.PostTypeId = 2
      AND p.OwnerUserId IS NOT NULL
      AND p.Tags IS NOT NULL AND LENGTH(TRIM(p.Tags)) > 2
    GROUP BY p.OwnerUserId, LOWER(TRIM(tag_unnested.tag_name))
),
UserPrimaryTag AS (
    SELECT
        utt.UserId,
        utt.TagName AS TopAnswerTag,
        utt.AnswerCountForTag AS TopTagAnswerCount,
        ROW_NUMBER() OVER(PARTITION BY utt.UserId ORDER BY utt.AnswerScoreForTag DESC, utt.AnswerCountForTag DESC) AS rn
    FROM UserTopAnswerTags utt
),
UsersInvolvedInClosedPosts AS (
    SELECT DISTINCT p.OwnerUserId AS UserId
    FROM Posts p
    WHERE p.ClosedDate IS NOT NULL AND p.OwnerUserId IS NOT NULL
    UNION
    SELECT DISTINCT c.UserId
    FROM Comments c
    JOIN Posts p ON c.PostId = p.Id
    WHERE p.ClosedDate IS NOT NULL AND c.UserId IS NOT NULL
)
SELECT
    u.Id AS UserId,
    COALESCE(u.DisplayName, 'Anonymous User #' || u.Id) AS DisplayName,
    u.Reputation,
    u.Views AS UserProfileViews,
    COALESCE(uas.TotalAnswers, 0) AS TotalAnswersProvided,
    COALESCE(uas.TotalAnswerScore, 0) AS TotalAnswersScore,
    COALESCE(uas.AverageAnswerScore, 0.0) AS AverageAnswerScore,
    COALESCE(uas.TotalUpVotesOnAnswers, 0) AS TotalUpVotesOnAnswers,
    COALESCE(uas.TotalDownVotesOnAnswers, 0) AS TotalDownVotesOnAnswers,
    COALESCE(uaea.TotalSelfEditsOnOwnPosts, 0) AS TotalSelfEditsOnOwnPosts,
    COALESCE(uaea.TotalOtherUserEditsOnOwnPosts, 0) AS TotalOtherUserEditsOnOwnPosts,
    COALESCE(uaea.TotalOwnPostsClosed, 0) AS OwnPostsClosedCount,
    COALESCE(uaea.TotalOwnPostsReopened, 0) AS OwnPostsReopenedCount,
    COALESCE(uci.TotalCommentsMade, 0) AS TotalCommentsMade,
    COALESCE(uci.TotalCommentScore, 0) AS TotalCommentsScore,
    COALESCE(uci.CommentsOnDownvotedPosts, 0) AS CommentsOnDownvotedPostsCount,
    upt.TopAnswerTag,
    upt.TopTagAnswerCount,
    (COALESCE(uas.TotalUpVotesOnAnswers, 0) - COALESCE(uas.TotalDownVotesOnAnswers, 0)) AS NetAnswerVotes,
    (
        COALESCE(uas.TotalDownVotesOnAnswers, 0) * 1.5
        + COALESCE(uaea.TotalOwnPostsClosed, 0) * 5
        + COALESCE(uaea.TotalOtherUserEditsOnOwnPosts, 0) * 0.8
        + COALESCE(uci.CommentsOnDownvotedPosts, 0) * 2
        + CASE WHEN uiicp.UserId IS NOT NULL THEN 10 ELSE 0 END
    ) AS ControversyScore,
    CASE
        WHEN u.LastAccessDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '3 months' THEN 'Active'
        WHEN u.LastAccessDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year' THEN 'Recently Active'
        ELSE 'Inactive'
    END AS UserActivityStatus,
    CASE WHEN uiicp.UserId IS NOT NULL THEN TRUE ELSE FALSE END AS IsInvolvedInClosedPostsFlag,
    RANK() OVER (
      ORDER BY u.Reputation DESC,
               COALESCE(uas.TotalAnswerScore, 0) DESC,
               (COALESCE(uas.TotalUpVotesOnAnswers, 0) - COALESCE(uas.TotalDownVotesOnAnswers, 0)) DESC,
               (
                 COALESCE(uas.TotalDownVotesOnAnswers, 0) * 1.5
                 + COALESCE(uaea.TotalOwnPostsClosed, 0) * 5
                 + COALESCE(uaea.TotalOtherUserEditsOnOwnPosts, 0) * 0.8
                 + COALESCE(uci.CommentsOnDownvotedPosts, 0) * 2
                 + CASE WHEN uiicp.UserId IS NOT NULL THEN 10 ELSE 0 END
               ) DESC
    ) AS UserEngagementRank
FROM Users u
LEFT JOIN UserAnswerSummary uas ON u.Id = uas.UserId
LEFT JOIN AggregatedUserEditActivity uaea ON u.Id = uaea.UserId
LEFT JOIN UserCommentInteraction uci ON u.Id = uci.UserId
LEFT JOIN (
    SELECT UserId, TopAnswerTag, TopTagAnswerCount
    FROM UserPrimaryTag
    WHERE rn = 1
) upt ON u.Id = upt.UserId
LEFT JOIN UsersInvolvedInClosedPosts uiicp ON u.Id = uiicp.UserId
WHERE
    u.Reputation >= 1000
    AND (COALESCE(uas.TotalAnswers, 0) > 5 OR COALESCE(uci.TotalCommentsMade, 0) > 10)
    AND u.CreationDate <= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year'
    AND (u.Location IS NOT NULL AND LENGTH(TRIM(u.Location)) > 0)
GROUP BY
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.Views,
    uas.TotalAnswers,
    uas.TotalAnswerScore,
    uas.AverageAnswerScore,
    uas.TotalUpVotesOnAnswers,
    uas.TotalDownVotesOnAnswers,
    uaea.TotalSelfEditsOnOwnPosts,
    uaea.TotalOtherUserEditsOnOwnPosts,
    uaea.TotalOwnPostsClosed,
    uaea.TotalOwnPostsReopened,
    uaea.TotalOwnPostsDeleted,
    uaea.TotalOwnPostsUndeleted,
    uci.TotalCommentsMade,
    uci.TotalCommentScore,
    uci.CommentsOnDownvotedPosts,
    uci.CommentsOnOwnPosts,
    upt.TopAnswerTag,
    upt.TopTagAnswerCount,
    u.LastAccessDate,
    uiicp.UserId,
    u.CreationDate
ORDER BY
    UserEngagementRank ASC,
    u.CreationDate DESC
LIMIT 200;