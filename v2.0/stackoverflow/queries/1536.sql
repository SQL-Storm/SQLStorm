-- {"query": "1536.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2188}
WITH UserActivityMetrics AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Location,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionsPosted,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswersPosted,
        COALESCE(SUM(p.Score), 0) AS TotalPostScoreReceived,
        COALESCE(SUM(c.Score), 0) AS TotalCommentScoreReceived,
        COALESCE(COUNT(DISTINCT p.Id), 0) AS TotalPostsCreated,
        COALESCE(COUNT(DISTINCT c.Id), 0) AS TotalCommentsCreated,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpvotesGiven,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownvotesGiven,
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - u.LastAccessDate)) / 86400.0 AS DaysSinceLastAccess,
        AVG(u.Reputation) OVER (PARTITION BY u.Location) AS AvgReputationInLocation
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.Views, u.UpVotes, u.DownVotes
),
PostEngagementAndHistory AS (
    SELECT
        peh_base.PostId,
        peh_base.PostTypeId,
        peh_base.PostTypeName,
        peh_base.PostCreationDate,
        peh_base.Score,
        peh_base.ViewCount,
        peh_base.AnswerCount,
        peh_base.CommentCount,
        peh_base.FavoriteCount,
        peh_base.OwnerUserId,
        peh_base.Title,
        peh_base.Tags,
        peh_base.LastEditDate,
        peh_base.ClosedDate,
        peh_base.ParentId,
        peh_base.LastHistoryEventDate,
        peh_base.PostHistoryTypeId,
        peh_base.HistoryUserId,
        peh_base.CloseReasonTypeName,
        CASE WHEN peh_base.ClosedDate IS NOT NULL THEN
            EXTRACT(EPOCH FROM (peh_base.ClosedDate - peh_base.PostCreationDate)) / 86400.0
        ELSE NULL END AS DaysToClose,
        CAST(peh_base.Score AS numeric) / NULLIF(peh_base.ViewCount, 0) AS ScorePerView,
        COALESCE(array_length(string_to_array(substr(peh_base.Tags, 2, char_length(peh_base.Tags) - 2), '><'), 1), 0) AS NumTags,
        EXTRACT(EPOCH FROM (COALESCE(peh_base.LastEditDate, peh_base.PostCreationDate) - peh_base.PostCreationDate)) / 86400.0 AS DaysToFirstEditOrCreation
    FROM (
        SELECT
            p.Id AS PostId,
            p.PostTypeId,
            pt.Name AS PostTypeName,
            p.CreationDate AS PostCreationDate,
            p.Score,
            p.ViewCount,
            p.AnswerCount,
            p.CommentCount,
            p.FavoriteCount,
            p.OwnerUserId,
            p.Title,
            p.Tags,
            p.LastEditDate,
            p.ClosedDate,
            p.ParentId,
            ph.CreationDate AS LastHistoryEventDate,
            ph.PostHistoryTypeId,
            ph.UserId AS HistoryUserId,
            crt.Name AS CloseReasonTypeName,
            ROW_NUMBER() OVER(PARTITION BY p.Id ORDER BY ph.CreationDate DESC NULLS LAST, ph.PostHistoryTypeId DESC NULLS LAST) AS rn_history
        FROM Posts p
        JOIN PostTypes pt ON p.PostTypeId = pt.Id
        LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4,5,6,10,11,12,13,19,20,35,36)
        LEFT JOIN CloseReasonTypes crt ON ph.PostHistoryTypeId = 10 AND crt.Id = (CASE WHEN ph.Comment ~ '^[0-9]+$' THEN CAST(ph.Comment AS smallint) ELSE NULL END)
    ) AS peh_base
    WHERE peh_base.rn_history = 1 OR peh_base.LastHistoryEventDate IS NULL
),
TagAggregates AS (
    SELECT
        LOWER(TRIM(tag_name.tag)) AS TagName,
        COUNT(DISTINCT peh.PostId) AS TaggedPostsCount,
        SUM(peh.Score) AS TagTotalScore,
        AVG(peh.Score) AS TagAvgScore,
        AVG(CASE WHEN peh.PostTypeId = 1 THEN peh.ViewCount END) AS TagAvgQuestionViewCount,
        COUNT(DISTINCT peh.OwnerUserId) AS UniqueContributors,
        MAX(peh.PostCreationDate) AS LatestTagActivity
    FROM PostEngagementAndHistory peh,
         unnest(string_to_array(substr(peh.Tags, 2, char_length(peh.Tags) - 2), '><')) AS tag_name(tag)
    WHERE peh.Tags IS NOT NULL AND peh.Tags <> '' AND peh.Tags <> '<>'
    GROUP BY LOWER(TRIM(tag_name.tag))
),
UserPostTypeAvgScores AS (
    SELECT
        p.OwnerUserId,
        p.PostTypeId,
        AVG(p.Score) AS AvgScoreForUserPostType
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, p.PostTypeId
),
CombinedPostAnalysis AS (
    SELECT
        'Question' AS PostCategory,
        uam.UserId,
        COALESCE(uam.DisplayName, 'Anonymous') AS UserDisplayName,
        uam.Reputation,
        peh.PostId,
        peh.Title,
        peh.PostCreationDate,
        peh.Score AS PostScore,
        peh.ViewCount,
        peh.AnswerCount,
        peh.CommentCount,
        peh.FavoriteCount,
        peh.DaysToClose,
        peh.ScorePerView,
        peh.NumTags,
        peh.ClosedDate,
        peh.CloseReasonTypeName,
        (peh.Score + COALESCE(peh.FavoriteCount, 0) * 5 + COALESCE(peh.AnswerCount, 0) * 3 + peh.ViewCount / 100.0) AS CalculatedImpactScore,
        RANK() OVER (PARTITION BY peh.PostTypeId ORDER BY peh.Score DESC, peh.ViewCount DESC, peh.FavoriteCount DESC) AS RankWithinPostType,
        (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.PostTypeId = peh.PostTypeId) AS GlobalAvgScoreForPostType,
        (SELECT u_pa.AvgScoreForUserPostType FROM UserPostTypeAvgScores u_pa WHERE u_pa.OwnerUserId = peh.OwnerUserId AND u_pa.PostTypeId = peh.PostTypeId) AS UserAvgScoreForPostType,
        CASE
            WHEN peh.Score > (SELECT u_pa.AvgScoreForUserPostType FROM UserPostTypeAvgScores u_pa WHERE u_pa.OwnerUserId = peh.OwnerUserId AND u_pa.PostTypeId = peh.PostTypeId) THEN TRUE
            ELSE FALSE
        END AS IsAboveUserAverageForType,
        CASE
            WHEN peh.ClosedDate IS NOT NULL AND peh.CloseReasonTypeName LIKE '%Duplicate%' THEN 'Closed as Duplicate'
            WHEN peh.ClosedDate IS NOT NULL THEN 'Closed for Other Reason'
            WHEN peh.LastEditDate IS NOT NULL AND peh.LastEditDate > peh.PostCreationDate THEN 'Edited'
            ELSE 'Original'
        END AS PostStatusCategory,
        EXISTS (
            SELECT 1
            FROM Comments c
            WHERE c.PostId = peh.PostId
            AND c.CreationDate > COALESCE(peh.LastEditDate, peh.PostCreationDate)
        ) AS HasRecentCommentAfterEdit,
        peh.Tags
    FROM UserActivityMetrics uam
    INNER JOIN PostEngagementAndHistory peh ON uam.UserId = peh.OwnerUserId
    WHERE
        peh.PostTypeId = 1
        AND peh.ViewCount > 5000
        AND peh.AnswerCount >= 1
        AND peh.Score > 25
        AND uam.Reputation > 7500
        AND peh.PostCreationDate >= CAST('2020-01-01' AS timestamp)
)
SELECT *
FROM CombinedPostAnalysis
ORDER BY CalculatedImpactScore DESC, RankWithinPostType ASC;